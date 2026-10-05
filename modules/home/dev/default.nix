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
    home.packages = with pkgs; [
      # terminal
      ghostty        # gpu-accelerated terminal
      yazi           # terminal file manager
      lazygit        # terminal UI for git
      fastfetch      # system info display (neofetch was removed from nixpkgs)
      nnn            # terminal file manager
      tmux           # terminal multiplexer
      claude-code    # AI coding assistant
      herdr          # terminal workspace manager for AI coding agents

      # archives
      zip
      xz
      unzip
      p7zip

      # utils
      uv             # fast Python package manager
      git
      ripgrep        # recursively searches directories for a regex pattern
      fd             # simple, fast alternative to find
      wl-clipboard   # Wayland clipboard (needed for neovim yank to system clipboard)
      zoxide         # smarter cd command
      jq             # command-line JSON processor
      yq-go          # yaml processor
      eza            # modern replacement for ls
      tree           # display directories as trees
      file           # determine file type
      which          # locate a command
      gnused         # GNU sed
      gnutar         # GNU tar
      gawk           # GNU awk
      zstd           # fast compression algorithm
      gnupg          # GNU privacy guard

      # networking tools
      mtr            # network diagnostic tool
      iperf3         # network bandwidth measurement
      dnsutils       # dig + nslookup
      ldns           # drill command (dig replacement)
      aria2          # multi-protocol download utility
      socat          # multipurpose relay (netcat replacement)
      netcat-openbsd # nc -U: herdr-jump + worktrunk plugin talk to herdr's socket
      nmap           # network discovery and security auditing
      ipcalc         # IPv4/v6 address calculator

      # monitoring
      btop           # resource monitor (htop replacement)
      iotop          # IO monitoring
      iftop          # network monitoring
      strace         # system call monitoring
      ltrace         # library call monitoring
      lsof           # list open files
      sysstat        # system performance tools
      lm_sensors     # hardware sensors
      ethtool        # ethernet device settings
      pciutils       # lspci
      usbutils       # lsusb

      # productivity
      hugo           # static site generator
      glow           # markdown previewer in terminal

      # nix related
      nix-output-monitor  # nix with detailed log output (nom command)

      # misc
      cowsay         # configurable talking cow
    ];

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

    # Ghostty
    xdg.configFile."ghostty/config".source = ../../../dotfiles/ghostty/config;

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
        nrs = "nh os switch";
        zshconfig = "nvim ~/.zshrc";
        clauded = "claude --dangerously-skip-permissions";
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
