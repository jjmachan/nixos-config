# Remote Dev: the Mac as a Window onto the nixbox

How day-to-day dev work runs: agents and long sessions live on the `nixbox`, and the
MacBook is mostly a terminal pointed at it. Built to hold up on slow or flaky internet.

> **Status:** designed, not yet built. This line goes away once the mosh changes are merged.

## The idea

```
MacBook (Ghostty)                         nixbox (always on)
┌──────────────────┐   mosh over          ┌────────────────────────────────┐
│ `nixbox` alias   │──Tailscale (UDP)────►│ mosh-server ─► herdr client    │
│                  │                      │                  │             │
│ local dev module │                      │          herdr server          │
│ (offline backup) │                      │   ├─ claude (agent sessions)   │
└──────────────────┘                      │   ├─ nvim, shells, dev servers │
                                          │   └─ …keeps running when you   │
                                          │      disconnect                │
                                          └────────────────────────────────┘
```

Three layers, each with one job:

- **herdr server** (on the nixbox) keeps your work alive: it owns the panes, so
  agents keep running when the laptop sleeps, the wifi drops or you close the
  terminal. Running `herdr` reattaches to the same `default` session.
- **mosh** keeps the connection usable on a bad link. It runs over UDP, survives
  sleep and network changes (café wifi → phone hotspot), and echoes your typing
  locally instead of waiting a full round trip for each key.
- **Tailscale** makes `nixbox` reachable from anywhere, with no public ports. When a
  network blocks direct connections it falls back to a relay: slower, but still working.

## Daily use

| You want to… | Do this |
|---|---|
| Get into your sessions | `nixbox` (on the Mac) |
| Leave, keeping everything running | `ctrl+g q` (herdr detach) or just close the lid |
| Come back | `nixbox` again |
| Try herdr's own remote mode instead | `herdr --remote nixbox` |
| See a dev server running on the nixbox | open `http://nixbox:<port>` on the Mac (the server must listen on `0.0.0.0`, not `localhost`) |
| Copy text from the nixbox to the Mac | select it in herdr or yank in nvim; it travels to the Mac clipboard via OSC 52 |
| Work with no internet at all | use the Mac locally: the same herdr, nvim and claude are installed there; move work with git |

The `nixbox` alias expands to:

```sh
mosh --server='MOSH_SERVER_NETWORK_TMOUT=259200 mosh-server' nixbox -- herdr
```

The timeout makes a mosh-server whose laptop never comes back exit after 3 days.
That loses nothing, because herdr holds the work, not mosh.

## Where things run

- **Long-running agents and Claude sessions:** on the nixbox, inside herdr. It never
  sleeps, and closing the laptop doesn't kill anything.
- **Short offline work:** on the Mac. Claude sessions are tied to the machine and the
  absolute path (`/Users/…` vs `/home/…`), so a session started on the Mac stays on the Mac.
- **The hermes agents (Penny, Alfred, Iris):** separate MicroVMs on the nixbox,
  unaffected by any of this. See `hosts/nixbox/agents/`.

## How it's configured

| Piece | Where |
|---|---|
| `mosh` package (client + server, every box) | `modules/home/dev/packages.nix` |
| mosh on the nixbox, `openFirewall = false` | `hosts/nixbox/configuration.nix` |
| `nixbox` alias | `hosts/macbook/home.nix` |
| herdr config (detach key, mouse, clipboard) | `dotfiles/herdr/config.toml` |

mosh needs UDP ports 60000–61000. They're **not** opened on the LAN: the nixbox
already accepts all traffic arriving over Tailscale (`tailscale0`), so mosh
works over Tailscale only. That's deliberate, with one less open port.

## Gotchas

- **No scrollback in mosh.** mosh only syncs the visible screen. Scroll inside herdr instead.
- **Clipboard under mosh still needs testing.** herdr chooses OSC 52 when it sees
  `SSH_CONNECTION`/`SSH_TTY`. Whether those survive into a mosh session is the one
  link not yet verified.
- **SSH to the nixbox is Tailscale SSH**, not OpenSSH. mosh only uses SSH to start up,
  so this doesn't matter, but it explains the odd processes in `ps`.
- **Two clients on one tab:** the one that last interacted with it sets the pane size.
  When the other detaches, sizes snap back.
- **Leftover mosh-servers:** harmless, and they clear themselves after 3 days (see above).

## Not done yet (on the README roadmap)

- **Phone notifications** when an agent is waiting on input (a Claude Code hook → ntfy/Telegram).
- **Real offline mode:** sync `~/workspace` between the Mac and the nixbox with Syncthing.
- **Per-project herdr sessions:** change the alias to `nixbox [session]` →
  `herdr --session <name>`.
