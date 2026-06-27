# Self-hosted media stack — shared wiring for all services.
#
# Architecture (see also the per-service files imported below):
#   Jellyseerr -> Sonarr/Radarr -> (Prowlarr indexers) -> qBittorrent
#   -> import into /srv/media -> Jellyfin streams it.
#
# Design notes:
#   * Single media root so Sonarr/Radarr can hardlink/atomic-move instead of copy.
#   * Shared "media" group + setgid dirs + UMask=0002 so every service can
#     read/write the library without permission fights.
#   * Nothing is exposed publicly: admin UIs are reachable only over the
#     tailscale0 interface; Jellyfin + Jellyseerr also get HTTPS via tailscale serve.
{ config, pkgs, lib, ... }:

{
  imports = [
    ./jellyfin.nix
    ./arr.nix
    ./download.nix
    ./jellyseerr.nix
    ./tunnel.nix
  ];

  # Shared group for everything that touches the media library.
  users.groups.media = { };

  # Media library layout. 2775 = setgid so new files inherit the media group.
  systemd.tmpfiles.rules = [
    "d /srv/media           2775 root media - -"
    "d /srv/media/movies    2775 root media - -"
    "d /srv/media/tv        2775 root media - -"
    "d /srv/media/downloads 2775 root media - -"
  ];

  # Admin/web UIs reachable ONLY over the tailnet, never LAN/internet.
  # (We deliberately do not use each service's openFirewall, which opens all interfaces.)
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    8096  # jellyfin
    5055  # jellyseerr
    8989  # sonarr
    7878  # radarr
    9696  # prowlarr
    8080  # qbittorrent webui
    6767  # bazarr (if enabled)
  ];

  # Allow the tailscale daemon to provision the MagicDNS HTTPS cert.
  services.tailscale.permitCertUid = "root";

  # Expose the two user-facing apps over HTTPS on the tailnet.
  #   https://nixos.tail66a220.ts.net        -> Jellyfin
  #   https://nixos.tail66a220.ts.net:5055   -> Jellyseerr
  # (No declarative serve option exists in 25.11, so drive the CLI from a oneshot.)
  systemd.services.tailscale-serve = {
    description = "Expose Jellyfin/Jellyseerr over tailscale serve (HTTPS)";
    after = [ "tailscaled.service" "jellyfin.service" "jellyseerr.service" ];
    wants = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    # Retry until the tailscale backend is past "NoState"/"Starting" and serve
    # commands succeed — tailscaled may still be coming up after a restart.
    script = ''
      for i in $(seq 1 30); do
        if ${pkgs.tailscale}/bin/tailscale serve --bg --https=443 http://127.0.0.1:8096; then
          ${pkgs.tailscale}/bin/tailscale serve --bg --https=5055 http://127.0.0.1:5055
          exit 0
        fi
        sleep 2
      done
      echo "tailscale serve: backend never became ready" >&2
      exit 1
    '';
  };
}
