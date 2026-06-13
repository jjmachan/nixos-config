# Jellyseerr — the request/discovery UI in front of Jellyfin + Sonarr/Radarr.
#
# Runs as the module's DynamicUser (no media-file access needed — it only talks
# to service APIs). configDir is left at the default; setting it triggers a
# known 25.11 startup bug.
{ config, pkgs, lib, ... }:

{
  services.jellyseerr.enable = true; # port 5055, tailnet-only via firewall + serve
}
