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

This is a single-host NixOS flake configuration for an x86_64-linux machine (hostname: "nixos", user: jjmachan).

**Flake inputs:** nixpkgs 26.05 (stable), claude-code-nix (sadjow/claude-code-nix — hourly auto-updated claude-code), home-manager 26.05, worktrunk, herdr (herdrdev/herdr — built from source, follows our nixpkgs), suika (local custom module at /home/jjmachan/suika-module — a self-evolving AI agent in a MicroVM).

### Key Files

- `flake.nix` — Defines inputs, overlay (claude-code from claude-code-nix), and wires together system + home-manager modules
- `system/configuration.nix` — NixOS system config: GNOME desktop, systemd-boot, PipeWire audio, Docker, Tailscale, OpenSSH, Suika service, passwordless sudo, lid-close-no-sleep (server use)
- `system/hardware-configuration.nix` — Auto-generated hardware config (Intel/KVM, EFI, NVMe)
- `home.nix` — Home Manager config: 70+ packages, program configs (neovim, zsh, zellij, git, gh), dotfile sourcing

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

- Home Manager is integrated as a NixOS module (not standalone) — changes deploy together with `nh os switch .`
- `useGlobalPkgs = true` — home-manager shares the system nixpkgs
- Overlay pattern: claude-code is pulled from sadjow/claude-code-nix via overlay in `flake.nix`
- Flake inputs reach `home.nix` via `home-manager.extraSpecialArgs = { inherit inputs; }` (used for herdr)
- New dotfiles must be `git add`ed before building — flakes only see git-tracked files
- State versions: system is 25.05, home-manager is 25.11 — never bump them on a release upgrade; they record what created on-disk state (e.g. seerr keeps /var/lib/jellyseerr because system < 26.05)
- Repo symlink: `~/.config/nixos` → actual repo location. `programs.nh.flake` and the `claude-code-update` systemd service both reference this symlink. To move the repo, update the symlink (`ln -sfn /new/path ~/.config/nixos`) — no rebuild needed.
