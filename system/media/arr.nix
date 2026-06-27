# The *arr stack — Sonarr (TV), Radarr (movies), Prowlarr (indexer manager).
#
# Sonarr/Radarr touch the media library, so they join the "media" group and
# run with a group-writable umask. Prowlarr only talks to indexers/APIs, so it
# stays on the module's DynamicUser (no media access needed).
{ config, pkgs, lib, ... }:

{
  services.sonarr = {
    enable = true;
    group = "media";
  };

  services.radarr = {
    enable = true;
    group = "media";
  };

  services.prowlarr.enable = true;

  # Optional: subtitles. Uncomment to enable Bazarr (port 6767 already firewalled).
  # services.bazarr = {
  #   enable = true;
  #   group = "media";
  # };

  # New files land group-writable so the whole stack (and Jellyfin) can use them.
  systemd.services.sonarr.serviceConfig.UMask = "0002";
  systemd.services.radarr.serviceConfig.UMask = "0002";
}
