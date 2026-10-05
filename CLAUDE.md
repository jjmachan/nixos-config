# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Deploy Commands

```bash
# Rebuild and switch to new system configuration
nh os switch .

# Test build without switching (dry run)
nh os switch . --dry

# Update all flake inputs
nix flake update

# Update a single flake input
nix flake lock --update-input <input-name>
```

## Architecture

One flake for jjmachan's machines: the nixbox (NixOS, x86_64-linux, hostname still "nixos"), the MacBook (standalone home-manager, aarch64-darwin), any other Linux box (`homeConfigurations."jjmachan@linux"`), and a tools-only `packages.<system>.dev-tools` bundle. All share `modules/home/dev`. See README for outputs and the roadmap.

**Flake inputs:** nixpkgs 26.05 (stable), claude-code-nix (sadjow/claude-code-nix — hourly auto-updated claude-code), home-manager 26.05, worktrunk, herdr (herdrdev/herdr — built from source, follows our nixpkgs), suika (local custom module at /home/jjmachan/suika-module — a self-evolving AI agent in a MicroVM).

### Key Files

- `flake.nix` — Defines inputs, overlay (claude-code from claude-code-nix), and wires together system + home-manager modules
- `hosts/nixbox/configuration.nix` — NixOS system config: GNOME desktop, systemd-boot, PipeWire audio, Docker, Tailscale, OpenSSH, Suika service, passwordless sudo, lid-close-no-sleep (server use)
- `hosts/nixbox/hardware-configuration.nix` — Auto-generated hardware config (Intel/KVM, EFI, NVMe)
- `hosts/nixbox/home.nix` — jjmachan's home on the nixbox: imports the dev + desktop modules, sets `dev.repoPath`, holds `home.stateVersion`, plus nixbox-only bits (Linux server diagnostics, `nrs` alias)
- `modules/home/dev/` — shared terminal dev module (packages, neovim, zsh, zellij, git, gh, herdr, dotfile sourcing). Importing it turns it on; options live under `dev.*`. Linux-only bits go behind `lib.optionals pkgs.stdenv.isLinux`; machine-specific bits go in the host
- `hosts/macbook/home.nix` — the Mac: dev + desktop modules, flakes in ~/.config/nix/nix.conf, Mac-only zsh (nix-daemon.sh in .zshenv — nothing else puts nix on PATH there; brew shellenv; nix re-prepended last so it wins over brew)
- `hosts/linux/home.nix` — any other Linux box: dev module only, `repoPath` null
- `modules/home/dev/packages.nix` — the dev package list as a function `pkgs: herdr: [...]`, shared by the module and `dev-tools`
- `modules/home/desktop/` — GUI-side home config (ghostty: package on Linux, config everywhere)
- `hosts/nixbox/{media,agents}/` — media stack and agent MicroVMs
- `nixosConfigurations.nixbox` is the real output; `nixos` is an alias until the hostname is renamed (nh picks the output named after the hostname)

### Dotfiles (`dotfiles/`)

- `nvim/` — LazyVim-based Neovim config with Python support, DAP debugging, diffview, git-blame, markview, jupytext, zellij-navigator plugins
- `herdr/config.toml` — herdr (primary multiplexer) config; only this file is linked, `~/.config/herdr` stays a real dir for herdr's logs/sockets/session state
- `herdr-plugins/worktrunk/` — herdr plugin, registered by a `home.activation` step via `herdr plugin link` against the repo path (not the store)
- `bin/` — `herdr-jump`, `wt-clone`, `wt-init`, linked into `~/.local/bin` (on `home.sessionPath`)
- `ghostty/config` — terminal config (tokyonight)
- `zellij/config.kdl` — Terminal multiplexer config, kept as a fallback to herdr (default mode: locked)
- `zsh/.p10k.zsh` — Powerlevel10k prompt theme config
- `zsh/key-bindings.zsh` — FZF key bindings for zsh

## Nix Conventions

- On the nixbox, Home Manager is a NixOS module — changes deploy together with `nh os switch .`. On the Mac it's standalone (`pkgsFor` in flake.nix builds pkgs with the same overlay + allowUnfree)
- Check a nixbox change from the Mac without building: `just check-nixbox`
- `useGlobalPkgs = true` — home-manager shares the system nixpkgs
- Overlay pattern: claude-code is pulled from sadjow/claude-code-nix via overlay in `flake.nix`
- Flake inputs reach home-manager modules via `home-manager.extraSpecialArgs = { inherit inputs; }` (used for herdr)
- New dotfiles must be `git add`ed before building — flakes only see git-tracked files
- State versions: system is 25.05, home-manager is 25.11 — never bump them on a release upgrade; they record what created on-disk state (e.g. seerr keeps /var/lib/jellyseerr because system < 26.05)
- Repo symlink: `~/.config/nixos` → actual repo location. `programs.nh.flake` and the `claude-code-update` systemd service both reference this symlink. To move the repo, update the symlink (`ln -sfn /new/path ~/.config/nixos`) — no rebuild needed.
