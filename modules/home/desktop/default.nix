# GUI-side home config for machines with a screen. The dev module covers
# everything that works over ssh; this covers what only a desktop uses.
{ pkgs, lib, ... }: {
  # Ghostty — nixpkgs' ghostty is Linux-only; on macOS the app comes from the
  # Homebrew cask and home-manager manages only its config.
  home.packages = lib.optionals pkgs.stdenv.isLinux [ pkgs.ghostty ];
  xdg.configFile."ghostty/config".source = ../../../dotfiles/ghostty/config;
}
