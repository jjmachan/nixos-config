# Rex

[Rex](https://www.superlogical.com/rex/docs) is a terminal multiplexer: a
server owns the terminals, and the Mac app is a client that shows them. The
Mac app runs its own server; the nixbox runs a second one that the Mac reaches
over ssh, so work there keeps running when the Mac sleeps or disconnects.

## Pieces

| Where | What | Set up by |
| ----- | ---- | --------- |
| Mac | Rex app, its server and the `rex` CLI | The app installs and updates itself (preview channel) |
| Mac | `~/.config/rex/init.lua`: key bindings and hosts | `dotfiles/rex/init.lua`, linked into the checkout by `modules/home/desktop` |
| Mac | `xterm-rex` terminfo and the ssh guard | Once, by hand: `rex terminfo setup` (see below) |
| nixbox | Personal Rex server, `rex` CLI, `xterm-rex` terminfo, ssh guard | `hosts/nixbox/home.nix`: the Rex flake's home-manager module, `services.rex.enable` |

## How the Mac reaches the nixbox

`init.lua` declares the host:

```lua
rex.host{ label = "nixbox", endpoint = "ssh://jjmachan@nixbox" }
```

so `rex -S nixbox ls` works from any Mac terminal. Rex runs the Mac's own
`ssh` (keys, `~/.ssh/config`), runs `rex` on the nixbox, and talks to the
personal server there. Nothing listens on the network but sshd. The Rex docs
recommend ssh for now because Rex doesn't authenticate callers itself yet: a
plain HTTP listener gives anyone who reaches it full control of the account.

If the Mac app doesn't list the host, add it once with **Add Remote Host…** and
`ssh://jjmachan@nixbox` (the docs say hosts don't sync to the GUI yet).

## Choices, and why

- **Personal server, not the NixOS module's shared or login server.** The docs:
  "If you're the only person using Rex on the machine, run a personal server."
  It runs as jjmachan, as the systemd user service `rex`
  (`journalctl --user -u rex`).
- **Linger.** A personal server stops when its account logs out, ending every
  session. `users.users.jjmachan.linger = true` (configuration.nix, added for
  herdr-core) keeps it running.
- **Key bindings only on the Mac.** A device takes its hosts and shortcuts from
  its home server, which for the Mac is its own. The nixbox has no `init.lua`;
  the Mac's alt keys work in nixbox sessions too.
- **Preview channel**, matching the Mac app. `flake.lock` pins the exact
  release; `just update rex` moves to the newest preview.
- **ssh guard on the nixbox.** Rex panes set `TERM=xterm-rex`. The guard makes
  ssh send `xterm-256color` to machines without that entry. It needs
  `programs.ssh.enable`, so home-manager now writes the nixbox's
  `~/.ssh/config` (there was none before).

## Upgrades

`just update rex`, then `just switch` on the nixbox. The running server keeps
the old version, and its sessions, until it restarts:

```sh
rex version          # installed
rex server status    # running
systemctl --user restart rex   # ends every session on it
```

The Mac app updates itself. Keep the two on the same channel.

## Mac terminfo and ssh guard

The Mac's `~/.ssh/config` is hand-managed (SkyPilot, gcloud), so Nix doesn't
own it. Run once:

```sh
rex terminfo setup     # ~/.terminfo entry, guard, Include line in ~/.ssh/config
rex terminfo status
```

A plain `ssh nixbox` from a Mac Rex pane then sends `xterm-256color`. That's
fine; Rex sessions opened on the nixbox itself (`-S nixbox`) run under the
nixbox server and get `xterm-rex`, which the nixbox has. Don't use
`rex terminfo host install nixbox`: it runs `tic` into `~/.terminfo` there,
which home-manager owns.
