# The dev module's packages as a plain list, so the flake can also offer them
# as the tools-only `dev-tools` bundle. herdr comes from its own flake input.
pkgs: herdr: with pkgs; [
  # terminal
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
  iftop          # network monitoring
  lsof           # list open files

  # productivity
  hugo           # static site generator
  glow           # markdown previewer in terminal

  # nix related
  nix-output-monitor  # nix with detailed log output (nom command)

  # misc
  cowsay         # configurable talking cow
]
++ lib.optionals stdenv.isLinux [
  netcat-openbsd # nc -U for herdr-jump + the worktrunk plugin (macOS's /usr/bin/nc already has it)
  wl-clipboard   # Wayland clipboard (neovim yank to system clipboard; macOS has pbcopy)
]
