# KOReader highlights pipeline — self-hosted Readwise-alike.
#
# Flow:
#   Kobo (KOReader + jjmachan/syncthing.koplugin fork)
#     --(Syncthing "kobo-shelf", receive-only here)--> /srv/media/books/kobo-shelf
#       --(highlights-ingest: parse .sdr/metadata.*.lua sidecars)--> SQLite
#         --(render)--> one Markdown note per book in `outputDir`
#
# Design notes:
#   * kobo-shelf is receive-only: the server never writes back to the device.
#   * The ingest script (highlights-ingest.py) is stdlib-only Python with a
#     vendored Lua-literal parser — nothing on the device is executed, and the
#     service needs plain python3, no package set.
#   * Books removed from the device keep their notes: ingest only ever updates
#     books whose sidecar is present; markdown files are never deleted.
#   * `outputDir` is a plain folder for now. Next step: host the Obsidian vault
#     on this box and point outputDir into it — Obsidian Sync then propagates
#     the notes to every device. Nothing else changes.
#
# Manual setup (once, after deploy):
#   1. Kobo: install the jjmachan/syncthing.koplugin fork (+ syncthing ARM
#      binary) into KOReader; share the books folder (send-only) as "kobo-shelf".
#   2. Server Syncthing GUI (tailnet, :8384): accept the Kobo device + folder,
#      pointing it at /srv/media/books/kobo-shelf.
{ config, pkgs, lib, ... }:

let
  shelfDir = "/srv/media/books/kobo-shelf";
  outputDir = "/srv/media/books/highlights"; # future: <obsidian vault>/Reading/Kobo Highlights
  # Own state dir: books.nix's .state is root-owned, and sqlite needs to create
  # the db plus journal/WAL files as the service user.
  stateDir = "/srv/media/books/.state/highlights";
  dbPath = "${stateDir}/highlights.db";
in
{
  systemd.tmpfiles.rules = [
    "d ${shelfDir}  2775 jjmachan media - -"
    "d ${outputDir} 2775 jjmachan media - -"
    "d ${stateDir}  0775 jjmachan media - -"
  ];

  # Server side of the device sync. The kobo device and its share MUST be
  # declared here: override* = false only stops the module from deleting
  # runtime-added entries — declared folders are still re-applied on every
  # rebuild, so a folder without a `devices` list gets its share wiped (this
  # silently broke phone book-sync once; see the pixel note in books.nix).
  # The Kobo's identity (cert/key/config) was pre-generated and lives on the
  # device at .adds/koreader/settings/syncthing/.
  services.syncthing.settings.devices.kobo.id =
    "LBTPZPY-FFD2HHP-37MK4JI-R5VZATZ-BKDNP2K-T375LHF-EJRSG7T-JNNW7AO";
  services.syncthing.settings.folders."kobo-shelf" = {
    path = shelfDir;
    label = "Kobo Shelf";
    type = "receiveonly";
    devices = [ "kobo" ];
  };

  systemd.services.highlights-ingest = {
    description = "Parse KOReader .sdr sidecars into SQLite + Markdown notes";
    serviceConfig = {
      Type = "oneshot";
      User = "jjmachan";
      Group = "media";
      UMask = "0002";
    };
    script = ''
      ${pkgs.python3}/bin/python3 ${./highlights-ingest.py} \
        --shelf ${shelfDir} \
        --db ${dbPath} \
        --out ${lib.escapeShellArg outputDir}
    '';
  };

  # The Kobo can't join the tailnet, so unlike the phone (which syncs over
  # tailscale0, see books.nix) it needs Syncthing reachable on the LAN. The box
  # sits behind home NAT with only the Cloudflare tunnel exposed publicly, so
  # opening these on all interfaces is effectively LAN-only. 21027/UDP is local
  # discovery — how the Kobo finds the server without global discovery servers.
  networking.firewall.allowedTCPPorts = [ 22000 ];
  networking.firewall.allowedUDPPorts = [ 22000 21027 ];

  # The device only syncs while KOReader is awake on WiFi, so ingest latency is
  # dominated by the device anyway — a relaxed timer is plenty.
  systemd.timers.highlights-ingest = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5m";
      OnUnitActiveSec = "15m";
      Unit = "highlights-ingest.service";
    };
  };
}
