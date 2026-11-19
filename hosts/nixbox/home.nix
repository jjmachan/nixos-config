# jjmachan's home on the nixbox: the shared dev module plus what only this
# machine needs.
{ config, pkgs, inputs, ... }: {
  imports = [
    ../../modules/home/dev
    ../../modules/home/desktop
    inputs.rex.homeManagerModules.default
  ];

  # Records what created this home's on-disk state; never bump it on upgrades.
  home.stateVersion = "25.11";

  # nh and the herdr plugin both reach the repo
  # through the ~/.config/nixos symlink.
  dev.repoPath = "${config.xdg.configHome}/nixos";

  # Rex: a personal server for this account, as a systemd user service, so the
  # Mac's Rex app can open sessions here over ssh (ssh://jjmachan@nixbox). It
  # outlives logout because the system config turns on linger. Also installs
  # rex and the xterm-rex terminfo. See docs/rex.md.
  services.rex.enable = true;
  # Lets programs.rex add its ssh guard to ~/.ssh/config, so ssh from a Rex pane
  # sends xterm-256color to machines without xterm-rex. Nothing else writes
  # ~/.ssh/config here. No default Host * block: ssh keeps its own defaults,
  # as it did with no ~/.ssh/config at all.
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
  };

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
}
