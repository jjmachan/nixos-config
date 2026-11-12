# GUI-side home config for machines with a screen. The dev module covers
# everything that works over ssh; this covers what only a desktop uses.
{ config, pkgs, lib, ... }:
let
  # The Herdr app (herdr.dev) installs and updates itself; only its config is
  # ours. It writes some of these files too (Settings, the theme picker), so
  # they link to the repo checkout, not the read-only store: its edits land in
  # `git diff`. Needs dev.repoPath.
  herdrApp = "${config.dev.repoPath}/dotfiles/herdr-app";
  linkHerdrApp = path: {
    name = "herdr-app/${path}";
    value.source = config.lib.file.mkOutOfStoreSymlink "${herdrApp}/${path}";
  };
in {
  # Ghostty — nixpkgs' ghostty is Linux-only; on macOS the app comes from the
  # Homebrew cask and home-manager manages only its config.
  home.packages = lib.optionals pkgs.stdenv.isLinux [ pkgs.ghostty ];
  xdg.configFile = {
    "ghostty/config".source = ../../../dotfiles/ghostty/config;
  } // lib.optionalAttrs (pkgs.stdenv.isDarwin && config.dev.repoPath != null) (builtins.listToAttrs (map linkHerdrApp [
    # Only these: the rest of ~/.config/herdr-app is the app's own state.
    # Edits behind a link don't hot-reload; switch layouts (ctrl-shift-l) to
    # pick them up.
    "settings.json"
    "keys.json"
    "themes/tty-night.json"
    "layouts/tty.json"
    "layouts/tty-zen.json"
    "mods/tty"
    "mods/tty-goto"
  ]));
}
