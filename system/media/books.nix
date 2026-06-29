# Ebook stack — Calibre-Web-Automated (CWA) + a watch-folder bridge + Syncthing.
#
# Flow:
#   phone --(Syncthing)--> /srv/media/books/archive  (the permanent MASTER copy)
#     --(books-bridge: copy new files)--> /srv/media/books/ingest
#       --(CWA auto-import; deletes from ingest)--> /srv/media/books/calibre-library
#         --> OPDS + KOSync --> Kobo (KOReader)
#
# Design notes:
#   * archive/ is canonical and never mutated by us — the bridge only COPIES out
#     of it, so your "folder where everything lives" stays intact.
#   * CWA's ingest dir is transient: CWA deletes files there after importing. The
#     bridge keeps per-file state markers (path+size+mtime) so it never re-copies
#     an already-imported file once CWA has consumed it.
#   * Only CWA is exposed publicly (via the Cloudflare tunnel, books.jjmachan.in);
#     it's login-gated. Syncthing's UI/protocol stay tailnet-only.
{ config, pkgs, lib, ... }:

{
  # First use of oci-containers in this config; docker is already enabled.
  virtualisation.oci-containers.backend = "docker";

  # Book library layout under the existing /srv/media root. 2775 = setgid so new
  # files inherit the media group (matches the rest of the media stack).
  systemd.tmpfiles.rules = [
    "d /srv/media/books                 2775 root     media - -"
    "d /srv/media/books/archive         2775 jjmachan media - -"
    "d /srv/media/books/ingest          2775 root     media - -"
    "d /srv/media/books/calibre-library 2775 root     media - -"
    "d /srv/media/books/config          2775 root     media - -"
    "d /srv/media/books/.state          0755 root     media - -"
  ];

  # Calibre-Web-Automated — library + OPDS + built-in KOSync.
  # Bound to 127.0.0.1: reachable ONLY through the Cloudflare tunnel, never on the
  # LAN/tailnet IP. (Docker-published ports bypass the nixos firewall, so exposure
  # is controlled by the bind address, not networking.firewall.)
  virtualisation.oci-containers.containers.calibre-web-automated = {
    image = "crocodilestick/calibre-web-automated:latest";
    ports = [ "127.0.0.1:8083:8083" ];
    environment = {
      PUID = "1001"; # jjmachan
      PGID = "986"; # media
      TZ = "America/Los_Angeles";
    };
    volumes = [
      "/srv/media/books/config:/config"
      "/srv/media/books/calibre-library:/calibre-library"
      "/srv/media/books/ingest:/cwa-book-ingest"
    ];
  };

  # Bridge: copy NEW files from the master archive into CWA's ingest (non-destructive).
  systemd.paths.books-bridge = {
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathModified = "/srv/media/books/archive";
      Unit = "books-bridge.service";
    };
  };

  systemd.services.books-bridge = {
    description = "Copy new ebooks from the master archive into CWA's ingest folder";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      UMask = "0002";
    };
    path = [ pkgs.coreutils pkgs.findutils ];
    script = ''
      set -eu
      ARCHIVE=/srv/media/books/archive
      INGEST=/srv/media/books/ingest
      STATE=/srv/media/books/.state
      find "$ARCHIVE" -type f \
        \( -iname '*.epub' -o -iname '*.mobi' -o -iname '*.azw3' -o -iname '*.pdf' \
           -o -iname '*.cbz' -o -iname '*.fb2' -o -iname '*.djvu' \) -print0 |
      while IFS= read -r -d "" f; do
        # Skip files still being written (download/Syncthing in progress): require the
        # size to be stable across a short interval, else a growing file gets copied as
        # partials and CWA imports duplicates. The timer re-runs to catch it once settled.
        size1=$(stat -c %s "$f")
        sleep 2
        size2=$(stat -c %s "$f" 2>/dev/null || echo skip)
        [ "$size1" != "$size2" ] && continue
        # Marker keyed on path+size+mtime: a given stable file is copied exactly once,
        # and stays "seen" even after CWA deletes it from the ingest folder.
        key=$(printf '%s' "$f-$size2-$(stat -c %Y "$f")" | md5sum | cut -d' ' -f1)
        marker="$STATE/$key"
        [ -e "$marker" ] && continue
        if cp -n -- "$f" "$INGEST/"; then
          : > "$marker"
        fi
      done
    '';
  };

  # Sweep on a timer too: PathModified isn't recursive and a file's final settle may
  # arrive between triggers, so the timer is the reliable pickup path. Short interval
  # keeps import latency low.
  systemd.timers.books-bridge = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "3m";
      Unit = "books-bridge.service";
    };
  };

  # Syncthing — phone <-> box sync of the master archive. Runs as jjmachan:media so
  # files land group-writable for the bridge. Pair the phone via the GUI on first run.
  services.syncthing = {
    enable = true;
    user = "jjmachan";
    group = "media";
    dataDir = "/srv/media/books";
    configDir = "/srv/media/books/.syncthing";
    # GUI defaults to 127.0.0.1 only; bind all interfaces so it's reachable over the
    # tailnet (the firewall above still restricts 8384 to tailscale0).
    guiAddress = "0.0.0.0:8384";
    overrideDevices = false; # don't clobber GUI-added devices on rebuild
    overrideFolders = false; # don't clobber GUI-added folders on rebuild
    settings.folders."books-archive" = {
      path = "/srv/media/books/archive";
      label = "Books";
    };
  };
  systemd.services.syncthing.serviceConfig.UMask = "0002";

  # Syncthing GUI (8384) + sync/discovery reachable only over the tailnet. Global
  # discovery + relays (outbound) still let the phone sync when off-tailnet.
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8384 22000 ];
  networking.firewall.interfaces."tailscale0".allowedUDPPorts = [ 22000 21027 ];
}
