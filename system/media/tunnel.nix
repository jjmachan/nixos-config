# Cloudflare Tunnel — exposes Jellyfin + Jellyseerr publicly on jjmachan.in.
#
# Outbound-only: cloudflared dials out to Cloudflare's edge, so there are no
# inbound ports and no port-forwarding (works behind home NAT). Only the two
# user-facing apps are routed; anything else returns 404. The admin apps
# (Sonarr/Radarr/Prowlarr/qBittorrent) stay tailnet-only.
#
# The tunnel credentials live at /var/lib/cloudflared/<id>.json — a SECRET kept
# out of git. The tunnel ID below is only an identifier, not sensitive.
{ ... }:
{
  services.cloudflared = {
    enable = true;
    tunnels."a12861ff-3c12-42d3-aa3c-9ff2254cfa8d" = {
      credentialsFile = "/var/lib/cloudflared/a12861ff-3c12-42d3-aa3c-9ff2254cfa8d.json";
      certificateFile = "/var/lib/cloudflared/cert.pem"; # silences origin-cert lookup warning
      default = "http_status:404"; # anything not listed below -> 404
      ingress = {
        "jellyfin.jjmachan.in" = "http://localhost:8096";
        "requests.jjmachan.in" = "http://localhost:5055";
      };
    };
  };
}
