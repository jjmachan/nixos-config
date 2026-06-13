# qBittorrent — the download client.
#
# Saves into /srv/media/downloads (same filesystem as the library) so Sonarr/Radarr
# can hardlink/atomic-move imports instead of slow copies. Set the actual save path
# and a real WebUI password in the web UI on first run (kept out of git).
{ config, pkgs, lib, ... }:

{
  services.qbittorrent = {
    enable = true;
    group = "media";
    # webuiPort = 8080;        # default
    # torrentingPort = 50000;  # set a fixed listen port if you want
  };

  systemd.services.qbittorrent.serviceConfig.UMask = "0002";
}
