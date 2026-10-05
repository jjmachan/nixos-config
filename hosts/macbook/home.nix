# jjmachan's home on the MacBook: standalone home-manager for now (nix-darwin
# comes later). Shell lines here are the live, Mac-only parts of the old stowed
# mydotfiles .zshrc; the shared parts are in the dev module.
{ config, lib, pkgs, ... }: {
  imports = [
    ../../modules/home/dev
    ../../modules/home/desktop
  ];

  # Standalone home-manager can't ask NixOS who the user is, so say it here.
  home.username = "jjmachan";
  home.homeDirectory = "/Users/jjmachan";
  # Records what created this home's on-disk state; never bump it on upgrades.
  home.stateVersion = "26.05";

  dev.repoPath = "${config.home.homeDirectory}/workspace/personal/nixos-config";

  # Flakes on for this user (/etc/nix/nix.conf leaves them off). nix.package is
  # only used to check the generated ~/.config/nix/nix.conf; it isn't installed,
  # so the daemon's nix stays the one on PATH.
  nix.package = pkgs.nix;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  programs.zsh = {
    # .zshenv runs for every zsh, including non-interactive `ssh mac cmd`.
    envExtra = ''
      # Nix itself. The installer's hook in /etc/zshrc is gone (macOS updates
      # reset that file), so without this nix isn't on PATH at all.
      if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
      fi
      [ -r "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
    '';

    profileExtra = ''
      eval "$(/opt/homebrew/bin/brew shellenv)"
    '';

    shellAliases = {
      hms = "nh home switch -c jjmachan@macbook";
      cpwd = "pwd | tr -d '\\n' | pbcopy && echo 'pwd copied to clipboard'";
    };

    initContent = lib.mkMerge [
      ''
        export LC_ALL=en_US.UTF-8
        export LANG=en_US.UTF-8

        # Tools installed outside nix (brew, curl installers)
        export GOPATH="$HOME/go"
        path+=("$GOPATH/bin")
        command -v fnm >/dev/null && eval "$(fnm env --use-on-cd)"
        export BUN_INSTALL="$HOME/.bun"
        path=("$BUN_INSTALL/bin" "$HOME/.npm-global/bin" "$HOME/.antigravity/antigravity/bin" $path)
        [ -s "$BUN_INSTALL/_bun" ] && source "$BUN_INSTALL/_bun"

        autoload -U +X bashcompinit && bashcompinit
        [ -r /opt/homebrew/etc/bash_completion.d/az ] && source /opt/homebrew/etc/bash_completion.d/az
        command -v terraform >/dev/null && complete -o nospace -C "$(command -v terraform)" terraform

        # Android / Java (Flow Lab)
        export JAVA_HOME="$(/usr/libexec/java_home -v 21 2>/dev/null)"
        export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
        export ANDROID_SDK_ROOT="$ANDROID_HOME"
        path=("$ANDROID_HOME/emulator" $path)

        export RAGAS_DO_NOT_TRACK=True
      ''
      # Last: macOS's path_helper (/etc/zprofile) and brew shellenv both push
      # their dirs ahead of nix's, so put nix back in front. typeset -U drops
      # the later duplicates.
      (lib.mkAfter ''
        typeset -U path
        path=("${config.home.profileDirectory}/bin" /nix/var/nix/profiles/default/bin $path)
      '')
    ];
  };
}
