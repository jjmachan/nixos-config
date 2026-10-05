# jjmachan's home on the nixbox: the shared dev module plus what only this
# machine needs.
{ config, pkgs, ... }: {
  imports = [
    ../../modules/home/dev
    ../../modules/home/desktop
  ];

  # Records what created this home's on-disk state; never bump it on upgrades.
  home.stateVersion = "25.11";

  # nh, the claude-code-update service and the herdr plugin all reach the repo
  # through the ~/.config/nixos symlink.
  dev.repoPath = "${config.xdg.configHome}/nixos";

  # Linux server diagnostics — about this machine, not the dev workflow.
  home.packages = with pkgs; [
    iotop          # IO monitoring
    strace         # system call monitoring
    ltrace         # library call monitoring
    sysstat        # system performance tools
    lm_sensors     # hardware sensors
    ethtool        # ethernet device settings
    pciutils       # lspci
    usbutils       # lsusb
  ];

  programs.zsh.shellAliases.nrs = "nh os switch";
}
