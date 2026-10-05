# Jellyfin — the streaming server, with Intel Quick Sync hardware transcoding.
{ config, pkgs, lib, ... }:

{
  services.jellyfin = {
    enable = true;
    group = "media"; # share the media library group; no openFirewall (tailnet-only)
  };

  # GPU access for hardware transcoding (i7-1260P iGPU at /dev/dri/renderD128).
  users.users.jellyfin.extraGroups = [ "render" "video" ];

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver   # iHD VAAPI driver for Gen11+ (Alder Lake)
      vpl-gpu-rt           # oneVPL runtime for QSV
      intel-compute-runtime
    ];
  };

  # Force the modern iHD driver for the jellyfin service.
  systemd.services.jellyfin.environment.LIBVA_DRIVER_NAME = "iHD";
}
