# The terminal dev setup shared by every machine: shell, editor, git, herdr,
# CLI tools. Importing this module turns it on; hosts only set dev.* options.
{pkgs, lib, config, inputs, ...}: let
  cfg = config.dev;
  herdr = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
in {
  options.dev.repoPath = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    example = "/home/jjmachan/.config/nixos";
    description = ''
      Checkout of this repo on the machine, if any. Steps that need live repo
      files (not store copies), such as linking herdr plugins, skip when null.
    '';
  };

  # programs.worktrunk below comes from worktrunk's own home-manager module.
  imports = [ inputs.worktrunk.homeModules.default ];

  config = {
    home.packages = import ./packages.nix pkgs herdr;

    # Neovim — LazyVim manages its own plugins
    programs.neovim = {
      enable = true;
      defaultEditor = true;
      # 26.05 defaults: no python3/ruby providers (LazyVim and jupytext.vim don't
      # use them). Check with :checkhealth provider if a plugin ever needs one.
      withPython3 = false;
      withRuby = false;
    };
    xdg.configFile."nvim".source = ../../../dotfiles/nvim;

    # Zellij — raw KDL config
    programs.zellij.enable = true;
    xdg.configFile."zellij/config.kdl".source = ../../../dotfiles/zellij/config.kdl;

    # Herdr — link only config.toml: herdr writes logs, sockets and session
    # state into ~/.config/herdr, so the directory itself must stay writable.
    xdg.configFile."herdr/config.toml".source = ../../../dotfiles/herdr/config.toml;

    # Herdr plugins are registered with `herdr plugin link`, which records an
    # absolute path in ~/.config/herdr/plugins.json. Point it at the repo checkout
    # rather than the store, so the path survives rebuilds and script edits take
    # effect without one.
    home.activation.herdrPlugins = lib.mkIf (cfg.repoPath != null) (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      plugin="${cfg.repoPath}/dotfiles/herdr-plugins/worktrunk"
      if [ -f "$plugin/herdr-plugin.toml" ] \
        && ! ${pkgs.gnugrep}/bin/grep -qs '"jjmachan.worktrunk"' "${config.xdg.configHome}/herdr/plugins.json"; then
        run ${herdr}/bin/herdr plugin link "$plugin" \
          || warnEcho "herdr: could not link the worktrunk plugin; run: herdr plugin link $plugin"
      fi
    '');

    # Helper scripts: herdr-jump (prefix+j popup), wt-clone / wt-init (worktrunk
    # bare-repo layout)
    home.file.".local/bin" = {
      source = ../../../dotfiles/bin;
      recursive = true;
    };
    home.sessionPath = [ "$HOME/.local/bin" ];

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
        clauded = "claude --dangerously-skip-permissions";
        cld = "claude --dangerously-skip-permissions";
        feynman = "CLAUDE_CONFIG_DIR=~/.feynman claude";
        wsc = "wt switch --create --execute=claude";  # worktree + agent in one go
        wtm = "wt -C main";                           # run wt from a bare-repo parent
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

          # Zoxide
          eval "$(zoxide init zsh)"

          # Auto-activate flake.nix devShells via direnv
          auto_flake_envrc() {
            if [[ -f "$PWD/flake.nix" && ! -f "$PWD/.envrc" ]]; then
              echo -e "source_up\nuse flake" > "$PWD/.envrc"
              direnv allow "$PWD"
            fi
          }
          chpwd_functions+=(auto_flake_envrc)
        ''
      ];
    };

    home.file.".p10k.zsh".source = ../../../dotfiles/zsh/.p10k.zsh;

    # fzf — fuzzy finder with shell integration (Ctrl+R history, Ctrl+T files, Alt+C dirs)
    programs.fzf = {
      enable = true;
      enableZshIntegration = true;
    };

    # Worktrunk — git worktree management for parallel AI agents
    programs.worktrunk = {
      enable = true;
      enableZshIntegration = true;
    };

    # Direnv — auto-load environment variables per directory, with nix-direnv for flake support
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    # nh — nicer nix CLI (`nh os switch`, `nh home switch`) with a diff before
    # each switch; NH_FLAKE points it at this repo when there's a checkout.
    programs.nh = {
      enable = true;
      flake = lib.mkIf (cfg.repoPath != null) cfg.repoPath;
    };

    programs.gh = {
      enable = true;
      gitCredentialHelper.enable = true;
    };

    programs.git = {
      enable = true;
      ignores = [ ".envrc" ".direnv" ];
      settings = {
        user = {
          name = "Jithin James";
          email = "jamesjithin97@gmail.com";
        };
        init.defaultBranch = "main";
      };
    };
  };
}
