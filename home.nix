{pkgs, lib, ...}: {
  home.packages = with pkgs; [
    # terminal
    ghostty        # gpu-accelerated terminal
    yazi           # terminal file manager
    lazygit        # terminal UI for git
    neofetch       # system info display
    nnn            # terminal file manager
    claude-code    # AI coding assistant

    # archives
    zip
    xz
    unzip
    p7zip

    # utils
    git
    ripgrep        # recursively searches directories for a regex pattern
    fd             # simple, fast alternative to find
    fzf            # command-line fuzzy finder
    direnv         # auto-load environment variables per directory
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
