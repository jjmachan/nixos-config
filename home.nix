{pkgs, lib, ...}: {
  home.packages = with pkgs; [
    ghostty
    yazi
    git
    ripgrep
    fd
    fzf
    direnv
    zoxide
    lazygit
  ];

  # Neovim — LazyVim manages its own plugins
  programs.neovim = {
    enable = true;
    defaultEditor = true;
  };
  xdg.configFile."nvim".source = ./dotfiles/nvim;

  # Zellij — raw KDL config
  programs.zellij.enable = true;
  xdg.configFile."zellij/config.kdl".source = ./dotfiles/zellij/config.kdl;

  # Zsh
  programs.zsh = {
    enable = true;

    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "docker" "vi-mode" "kubectl" ];
      extraConfig = ''
        DISABLE_AUTO_TITLE="true"
      '';
    };

    shellAliases = {
      dc = "docker compose";
      dk = "docker";
      zshconfig = "nvim ~/.zshrc";
    };

    initContent = lib.mkMerge [
      (lib.mkBefore ''
        # Powerlevel10k instant prompt
        if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
          source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
        fi
      '')
      ''
        # Powerlevel10k theme
        source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme

        # Source p10k config
        [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

        # Direnv
        eval "$(direnv hook zsh)"

        # Zoxide
        eval "$(zoxide init zsh)"
      ''
    ];
  };

  home.file.".p10k.zsh".source = ./dotfiles/zsh/.p10k.zsh;

  programs.claude-code.enable = true;

  programs.openclaw = {
    config = {
      gateway = {
        mode = "local";
        auth = {
          tokenFile = "/home/jjmachan/.secrets/gateway-auth-token";
        };
      };

      channels.telegram = {
        tokenFile = "/home/jjmachan/.secrets/telegram-bot-token";
        allowFrom = [ 322721507 ];
        groups = {
          "*" = { requireMention = true; };
        };
      };
    };

    instances.default = {
      enable = true;
      plugins = [];
    };
  };

  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
  };

  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Jithin James";
        email = "jamesjithin97@gmail.com";
      };
      init.defaultBranch = "main";
    };
  };
}
