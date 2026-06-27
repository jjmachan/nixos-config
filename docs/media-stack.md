# Self-Hosted Media Stack

Personal streaming service running natively on the `nixos` box: request a movie or
show, it gets downloaded automatically, and it shows up in Jellyfin ready to watch.

> **This doc contains no secrets** — no passwords, no API keys. Where credentials are
> needed it tells you *where they live / how to retrieve them*, not their values.

## How it fits together

```
Jellyseerr ──► Sonarr (TV) / Radarr (movies) ──► Prowlarr (indexers)
                          │
                          ▼
                     qBittorrent ──► /srv/media ──► Jellyfin ──► your devices
```

- **Jellyseerr** — request/discovery UI; you browse and click "Request".
- **Sonarr / Radarr** — take the request, find a release, send it to the download client, then import + rename into the library.
- **Prowlarr** — manages indexers (trackers) and feeds them to Sonarr/Radarr.
- **qBittorrent** — the download client.
- **Jellyfin** — streams the finished library (with hardware transcoding).

All run as **native NixOS services** (no Docker), declared under `system/media/`.

## Services

| Service | Port | NixOS module | State dir | User / Group |
|---|---|---|---|---|
| Jellyfin | 8096 | `services.jellyfin` | `/var/lib/jellyfin` | `jellyfin` / `media` |
| Jellyseerr | 5055 | `services.jellyseerr` | `/var/lib/jellyseerr` | DynamicUser |
| Sonarr (TV) | 8989 | `services.sonarr` | `/var/lib/sonarr` | `sonarr` / `media` |
| Radarr (movies) | 7878 | `services.radarr` | `/var/lib/radarr` | `radarr` / `media` |
| Prowlarr | 9696 | `services.prowlarr` | `/var/lib/private/prowlarr` | DynamicUser |
| qBittorrent | 8080 | `services.qbittorrent` | `/var/lib/qbittorrent` | `qbittorrent` / `media` |
| Bazarr (optional) | 6767 | `services.bazarr` | `/var/lib/bazarr` | `bazarr` / `media` |

## Config layout

The stack is a small, modular tree imported with one line (`./media`) from
`system/configuration.nix`:

| File | Holds |
|---|---|
| `system/media/default.nix` | Shared wiring: `media` group, `/srv/media` dirs, tailnet firewall, Tailscale Serve. Imports the rest. |
| `system/media/jellyfin.nix` | Jellyfin + Intel Quick Sync hardware transcoding |
| `system/media/arr.nix` | Sonarr + Radarr + Prowlarr (Bazarr commented-out) |
| `system/media/download.nix` | qBittorrent |
| `system/media/jellyseerr.nix` | Jellyseerr |
| `system/media/tunnel.nix` | Cloudflare Tunnel — public access for Jellyfin + Jellyseerr |

## Storage & permissions

Everything lives under a single root so downloads and the library are on the **same
filesystem**, which lets Sonarr/Radarr **hardlink** imports (instant, no copy, no double
disk use):

```
/srv/media/
  movies/      ← Radarr library
  tv/          ← Sonarr library
  downloads/   ← qBittorrent
```

Permission model (the #1 thing that breaks these setups):

- A shared **`media` group**; the file-touching services (jellyfin, sonarr, radarr,
  qbittorrent, bazarr) have `group = "media"`.
- `/srv/media` dirs are mode **`2775` (setgid)** so new files inherit the `media` group,
  and the writers run with **`UMask = 0002`** so files stay group-writable.
- Prowlarr and Jellyseerr touch **no media files** (they only call APIs), so they stay on
  the module's DynamicUser — no media access needed.

## Networking & remote access

Two access paths: **tailnet-only** for everything (incl. admin), and **public** for just
the two user-facing apps. Nothing is exposed to the LAN, and no inbound ports are opened.

### Tailnet (admin + everything)

- The admin UIs are opened **only on the `tailscale0` interface**
  (`networking.firewall.interfaces."tailscale0".allowedTCPPorts`), not via each service's
  `openFirewall`. Reach them over the tailnet at `http://nixos:<port>` (e.g.
  `http://nixos:8989` for Sonarr).
- The two user-facing apps are fronted by **Tailscale Serve** for HTTPS:

| App | URL |
|---|---|
| Jellyfin | `https://nixos.tail66a220.ts.net` |
| Jellyseerr | `https://nixos.tail66a220.ts.net:5055` |

Serve is set up by a `tailscale-serve` systemd oneshot in `default.nix` (with a retry
loop so it survives `tailscaled` restarting during a rebuild).

### Public (Cloudflare Tunnel)

Jellyfin and Jellyseerr are reachable from the public internet on the `jjmachan.in`
domain, via a **Cloudflare Tunnel** (`services.cloudflared` in `tunnel.nix`):

| App | Public URL |
|---|---|
| Jellyfin | `https://jellyfin.jjmachan.in` |
| Jellyseerr | `https://requests.jjmachan.in` |

How it works and why it's this way:

- **Outbound-only.** `cloudflared` dials out to Cloudflare's edge and holds the connection
  open, so there are **no inbound ports and no port-forwarding** — essential since the box
  is behind home NAT with no public IPv4. TLS is terminated at Cloudflare's edge.
- **Only these two hostnames are routed.** The tunnel `ingress` lists `jellyfin` → `:8096`
  and `requests` → `:5055`, with a `default = "http_status:404"` catch-all. The admin apps
  have **no public DNS record at all** — double protection.
- **DNS is on Cloudflare.** The whole `jjmachan.in` zone was moved from NS1 to Cloudflare
  (free plan requires the full zone). The apex Netlify site + email records were recreated
  as **DNS-only (grey cloud)**; only the two tunnel CNAMEs are proxied (orange).
- **Credentials** live at `/var/lib/cloudflared/<tunnel-id>.json` (+ `cert.pem`) — secrets,
  kept out of git. The tunnel ID in `tunnel.nix` is just an identifier.
- **Don't put Cloudflare Access in front of Jellyfin** — it breaks native TV/mobile apps.
  Public exposure relies on Jellyfin's own auth, so keep the admin password strong.

**Add another public service:** `cloudflared tunnel route dns <tunnel-id> <name>.jjmachan.in`,
then add `"<name>.jjmachan.in" = "http://localhost:<port>";` to the `ingress` in
`tunnel.nix` and `nh os switch`.

One-time setup recap (already done): `cloudflared tunnel login` (browser auth → `cert.pem`),
`cloudflared tunnel create jjmachan` (→ credentials JSON + tunnel ID), then
`cloudflared tunnel route dns` for each hostname; move the secrets into
`/var/lib/cloudflared/`.

## Hardware transcoding

The box has an Intel i7-1260P with a Quick Sync iGPU, used for on-the-fly transcoding:

- `hardware.graphics` with `intel-media-driver` + `vpl-gpu-rt` (in `jellyfin.nix`).
- The `jellyfin` user is in the `render` and `video` groups for `/dev/dri` access.
- `LIBVA_DRIVER_NAME=iHD` forces the modern Intel driver.

Verify the GPU exposes encode/decode profiles:

```bash
nix shell nixpkgs#libva-utils -c vainfo --display drm --device /dev/dri/renderD128
# expect: "Intel iHD driver ..." with VAProfileH264/HEVC VLD + EncSlice entries
```

In Jellyfin: **Dashboard → Playback → Transcoding** → enable VAAPI / Intel Quick Sync,
device `/dev/dri/renderD128`.

## Credentials & accounts (where, not what)

This doc deliberately stores **no secret values**. The accounts that exist and where their
credentials come from:

| Account | Where it lives / how to get it |
|---|---|
| Jellyfin admin | Created in the Jellyfin setup wizard on first load. |
| Jellyseerr | No separate password — you **sign in with your Jellyfin account**. |
| qBittorrent admin | A **temporary** password is printed once to `journalctl -u qbittorrent` on first start; set your own under Web UI → Options → Web UI. |
| Sonarr / Radarr / Prowlarr API keys | In each service's `config.xml` (e.g. `/var/lib/sonarr/.config/NzbDrone/config.xml`, `/var/lib/radarr/.config/Radarr/config.xml`, `/var/lib/private/prowlarr/config.xml`). Also shown in each app's **Settings → General**. |

## First-time runtime wiring

The NixOS config installs and runs the services; the *app-to-app* wiring is done once in
the web UIs. **Use `127.0.0.1` (not `localhost`) for every inter-service URL** — the
services bind IPv4, and `localhost` resolves to IPv6 `::1` first (which fails).

1. **qBittorrent** (`http://nixos:8080`): set a real password; set default save path to `/srv/media/downloads`.
2. **Prowlarr** (`http://nixos:9696`): add indexer(s); **Settings → Apps** → add Sonarr (`http://127.0.0.1:8989`) and Radarr (`http://127.0.0.1:7878`) so indexers sync.
3. **Sonarr** (`http://nixos:8989`) / **Radarr** (`http://nixos:7878`): add the qBittorrent download client (`127.0.0.1:8080`); add root folders `/srv/media/tv` and `/srv/media/movies`; enable "Use Hardlinks instead of Copy".
4. **Jellyfin** (`https://nixos.tail66a220.ts.net`): finish the wizard; add libraries → Shows = `/srv/media/tv`, Movies = `/srv/media/movies`.
5. **Jellyseerr** (`https://nixos.tail66a220.ts.net:5055`): sign in with Jellyfin (server `http://127.0.0.1:8096`); **Settings → Services** → add Sonarr and Radarr with a sensible default quality profile and the matching root folder.

After this, requesting a title in Jellyseerr flows all the way to Jellyfin automatically.

## Operating it

```bash
# Rebuild after changing any system/media/*.nix
nh os switch                 # or: sudo nixos-rebuild switch --flake ~/.config/nixos#nixos

# Service status / logs
systemctl status jellyfin sonarr radarr prowlarr jellyseerr qbittorrent
journalctl -u sonarr -f      # follow a service's log

# Where things live
#   library + downloads:  /srv/media/{movies,tv,downloads}
#   service state/config: /var/lib/<service>  (prowlarr: /var/lib/private/prowlarr)
```

## Gotchas & troubleshooting

Hard-won lessons from setting this up:

- **`localhost` vs `127.0.0.1`** — services bind IPv4 only; `localhost` resolves to IPv6
  `::1` first and the connection fails (Jellyseerr "Unable to connect to Jellyfin",
  Prowlarr app tests, etc.). Always use `127.0.0.1` for inter-service URLs.
- **Request downloads nothing → quality-profile mismatch.** If a request finds releases
  but grabs none, check the quality profile. The classic trap: the request used the
  **Ultra-HD (4K)** profile but only 1080p/720p releases exist, so every release is
  rejected ("…1080p is not wanted in profile"). Fix the series/movie profile, or set a
  sane **default quality profile** on the Jellyseerr → Sonarr/Radarr service and make sure
  **"4K Server"** isn't checked unless you actually run a 4K instance.
- **qBittorrent "Unauthorized" / blank page when reached by hostname.** Reach it once via
  IP, then Options → Web UI → uncheck "Enable Host header validation" (or add
  `nixos,nixos.tail66a220.ts.net` to the allowed hosts).
- **Empty root-folder dropdown in Jellyseerr.** Jellyseerr lists only what Sonarr/Radarr
  know about — add the root folder (`/srv/media/tv`, `/srv/media/movies`) **in
  Sonarr/Radarr first**.
- **Right Prowlarr app tile.** 8989 = Sonarr (TV), 7878 = Radarr (movies). Readarr (books)
  and Lidarr (music) are *not installed* — don't pick those tiles.
- **macOS can't resolve `*.tail66a220.ts.net`.** Use the official **Tailscale.app**, not
  the Homebrew `tailscale` daemon — the Homebrew daemon runs unprivileged
  (userspace-networking) and can't program macOS DNS, so MagicDNS names won't resolve.
- **Imported episodes don't show in Jellyfin.** Jellyfin's real-time monitor often misses
  hardlinked imports. Trigger **Dashboard → Scheduled Tasks → Scan All Libraries**, or wire
  **Sonarr/Radarr → Settings → Connect → Jellyfin** (On Import) so it auto-rescans.
- **Cloudflare auto-imports records as Proxied (orange).** After moving the zone, set
  everything that already existed to **DNS-only (grey)** — especially `smtp`/`imap`/`pop`/
  `webmail` (Cloudflare only proxies HTTP/S, so proxying these **breaks email**) and the
  Netlify apex/`www`. Only the `jellyfin`/`requests` tunnel CNAMEs should be orange.
- **`cloudflared tunnel login` → "Failed to fetch resource".** The auth URL times out if
  too long passes between generating it and clicking Authorize. Re-run `tunnel login` and
  authorize promptly (within a minute).

## Deferred / future

- **VPN for qBittorrent** — run the download client in a WireGuard network namespace so
  torrent traffic only goes over a VPN.
- **Bazarr** — auto-subtitles (scaffolded but commented out in `arr.nix`).
- **Declarative `*arr` settings** — the modules expose `settings`; could move non-secret
  config into Nix, with secrets via `environmentFiles` (keeping keys out of git).
