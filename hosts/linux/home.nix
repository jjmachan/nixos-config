# jjmachan's home on any Linux box with nix that isn't the nixbox (a VPS, a
# cloud dev VM): just the dev module, no repo checkout assumed.
#   nix run home-manager -- switch --flake github:jjmachan/nixos-config#jjmachan@linux
{ pkgs, ... }: {
  imports = [ ../../modules/home/dev ];

  home.username = "jjmachan";
  home.homeDirectory = "/home/jjmachan";
  # Records what created this home's on-disk state; never bump it on upgrades.
  home.stateVersion = "26.05";

  # Flakes on for this user, so the switch command above keeps working.
  # nix.package only validates the generated nix.conf; it isn't installed.
  nix.package = pkgs.nix;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
