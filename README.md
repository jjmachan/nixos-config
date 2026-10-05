# nixos-config

One flake for jjmachan's machines, built around a shared terminal dev module:

| Output | Machine | How it's applied |
|--------|---------|------------------|
| `nixosConfigurations.nixbox` | the nixbox (x86_64-linux, NixOS) | `nh os switch .` (`nixos` is an alias until the hostname rename) |
| `homeConfigurations."jjmachan@macbook"` | the MacBook (aarch64-darwin) | standalone home-manager: `hms` (`nh home switch -c jjmachan@macbook`) |
| `homeConfigurations."jjmachan@linux"` | any other Linux box with nix | `nix run home-manager -- switch --flake github:jjmachan/nixos-config#jjmachan@linux` |
| `packages.<system>.dev-tools` | a borrowed box | `nix shell github:jjmachan/nixos-config#dev-tools` (tools only, nothing persists) |

## Quick Start (nixbox)

```bash
git clone <repo-url> ~/workspace/personal/nixos-config
cd ~/workspace/personal/nixos-config
nh os switch .
```

## From the Mac

```bash
just sync          # push the current branch to the nixbox checkout
just check-nixbox  # is this checkout's nixbox config what the nixbox is running?
just brew-dupes    # brew formulae that nix now also provides
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
| `hosts/macbook/home.nix` | jjmachan's home on the Mac: dev + desktop modules, Mac-only shell setup |
| `hosts/linux/home.nix` | jjmachan's home on any other Linux box: dev module only |
| `modules/home/dev/` | Shared terminal dev setup (packages, shell, editor, git, herdr) for every machine; `packages.nix` is also the `dev-tools` bundle |
| `modules/home/desktop/` | GUI-side home config (ghostty) for machines with a screen |
| `dotfiles/` | App configs (neovim, zellij, zsh) |
| `docs/` | Project documentation — see [media-stack.md](docs/media-stack.md) |

## Important: Repo Location

Each host tells the dev module where its checkout is with `dev.repoPath` (null = no checkout; repo-dependent steps skip). On the nixbox that's the symlink at `~/.config/nixos`, which nh and the claude-code-update service also use. Clone the repo anywhere, then point the symlink at it:

```bash
ln -sfn /path/to/your/clone ~/.config/nixos
```

To move the repo later, just update the symlink — no rebuild needed.

## Flake Inputs

- **nixpkgs** — NixOS 26.05 (stable)
- **home-manager** — 26.05, a NixOS module on the nixbox, standalone elsewhere
- **claude-code-nix** — Hourly auto-updated Claude Code package
- **suika** — Local MicroVM module
- **worktrunk** — Git worktree management for parallel AI agents
- **herdr** — terminal workspace manager, built from source (follows our nixpkgs)

## Roadmap

Parked on purpose; decisions already made are recorded so the next step starts from them.

- **Mac phase 2: nix-darwin.** Move home-manager inside nix-darwin (a small documented migration), then manage GUI apps as declarative Homebrew casks, macOS defaults, karabiner (still stowed from mydotfiles), and drop the duplicate Tailscale (brew formula + app both run).
- **Mac ↔ nixbox handoff.** Default: work runs on the nixbox and the Mac is a window into it (ssh + herdr). For work started on the Mac, Syncthing for `~/workspace` with per-project folders. Constraints: Claude Code keys sessions by absolute path (`/Users/...` vs `/home/...`), live `.git` dirs must not be written from both sides at once, and `.venv` / `node_modules` are platform-specific and must be ignored.
- **Portable neovim.** Bundle the nvim config into `dev-tools` so borrowed boxes get the editor setup too, not just the binaries.
- **Rename the host `nixos` → `nixbox`.** Hostname, Tailscale/ssh name, justfile, nh; then drop the `nixos` output alias.
