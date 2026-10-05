# Seerr (formerly Jellyseerr) — the request/discovery UI in front of
# Jellyfin + Sonarr/Radarr. 26.05 renamed services.jellyseerr to services.seerr.
#
# Runs as the module's DynamicUser (no media-file access needed — it only talks
# to service APIs). configDir is left at the default, which stays at the old
# /var/lib/jellyseerr/config because system.stateVersion is below 26.05.
{ config, pkgs, lib, ... }:

{
  services.seerr.enable = true; # port 5055, tailnet-only via firewall + serve
}
