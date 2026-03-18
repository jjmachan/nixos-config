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

**Flake inputs:** nixpkgs 25.11 (stable), claude-code-nix (sadjow/claude-code-nix — hourly auto-updated claude-code), home-manager 25.11, suika (local custom module at /home/jjmachan/suika-module — a self-evolving AI agent in a MicroVM).

### Key Files

- `flake.nix` — Defines inputs, overlay (claude-code from claude-code-nix), and wires together system + home-manager modules
- `system/configuration.nix` — NixOS system config: GNOME desktop, systemd-boot, PipeWire audio, Docker, Tailscale, OpenSSH, Suika service, passwordless sudo, lid-close-no-sleep (server use)
- `system/hardware-configuration.nix` — Auto-generated hardware config (Intel/KVM, EFI, NVMe)
- `home.nix` — Home Manager config: 70+ packages, program configs (neovim, zsh, zellij, git, gh), dotfile sourcing

### Dotfiles (`dotfiles/`)

- `nvim/` — LazyVim-based Neovim config with Python support, Copilot, DAP debugging, diffview, git-blame, zellij-navigator plugins
- `zellij/config.kdl` — Terminal multiplexer config (default mode: locked, vim-aware autolock)
- `zsh/.p10k.zsh` — Powerlevel10k prompt theme config
- `zsh/key-bindings.zsh` — FZF key bindings for zsh

## Nix Conventions

- Home Manager is integrated as a NixOS module (not standalone) — changes deploy together with `nh os switch .`
- `useGlobalPkgs = true` — home-manager shares the system nixpkgs
- Overlay pattern: claude-code is pulled from sadjow/claude-code-nix via overlay in `flake.nix`
- State versions: system is 25.05, home-manager is 25.11
