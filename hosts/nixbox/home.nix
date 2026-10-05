# jjmachan's home on the nixbox: the shared dev module plus what only this
# machine needs.
{ config, ... }: {
  imports = [ ../../modules/home/dev ];

  # Records what created this home's on-disk state; never bump it on upgrades.
  home.stateVersion = "25.11";

  # nh, the claude-code-update service and the herdr plugin all reach the repo
  # through the ~/.config/nixos symlink.
  dev.repoPath = "${config.xdg.configHome}/nixos";
}
