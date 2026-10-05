# nixos-config

NixOS flake configuration for a single x86_64-linux machine.

## Quick Start

```bash
# Clone the repo
git clone <repo-url> ~/workspace/personal/nixos-config
cd ~/workspace/personal/nixos-config

# Build and switch to the configuration
nh os switch .
```

## Updating

```bash
# Update all inputs (nixpkgs, home-manager, claude-code, etc.)
nix flake update
nh os switch .

# Update a single input
nix flake lock --update-input <input-name>
nh os switch .
```

## Structure

| File | Purpose |
|------|---------|
| `flake.nix` | Flake inputs, overlays, module wiring |
| `hosts/nixbox/configuration.nix` | nixbox NixOS system config (desktop, boot, services) |
| `hosts/nixbox/hardware-configuration.nix` | Auto-generated hardware config |
| `hosts/nixbox/home.nix` | jjmachan's home on the nixbox: imports the dev module + nixbox-only bits |
| `modules/home/dev/` | Shared terminal dev setup (packages, shell, editor, git, herdr) for every machine |
| `dotfiles/` | App configs (neovim, zellij, zsh) |
| `docs/` | Project documentation — see [media-stack.md](docs/media-stack.md) |

## Important: Repo Location

The config references the repo via a symlink at `~/.config/nixos`. Clone the repo anywhere, then point the symlink at it:

```bash
ln -sfn /path/to/your/clone ~/.config/nixos
```

To move the repo later, just update the symlink — no rebuild needed.

## Flake Inputs

- **nixpkgs** — NixOS 26.05 (stable)
- **home-manager** — 26.05, integrated as a NixOS module
- **claude-code-nix** — Hourly auto-updated Claude Code package
- **suika** — Local MicroVM module
- **worktrunk** — Git worktree management for parallel AI agents
