# Run from the repo, on any machine. `sync` and `check-nixbox` are Mac-only:
# sync is one-way, Mac → nixbox, never the other way.

nixbox := "jjmachan@nixbox"
nixbox_repo := "workspace/personal/nixos-config"
# Flakes stay off in /etc/nix/nix.conf on the Mac, so turn them on per call.
nix := "nix --extra-experimental-features 'nix-command flakes'"

# List recipes
default:
    @just --list

# Home on the Mac or a Linux box, the whole OS on NixOS.
[doc("Apply this checkout on this machine (`just switch dry`: build and show the diff only)")]
switch mode="":
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{mode}}" in
        "") flags=() ;;
        dry) flags=(--dry) ;;
        *) echo "switch: expected nothing or 'dry', got '{{mode}}'" >&2; exit 2 ;;
    esac
    if [[ "$(uname -s)" == Darwin ]]; then
        cmd=(nh home switch -c jjmachan@macbook .)
    elif [[ -e /etc/NIXOS ]]; then
        # A NixOS switch can restart sshd/networking; as a child of a plain
        # ssh session it would die half-done. A herdr/tmux/zellij pane belongs
        # to its server, not the ssh connection, so it survives the drop.
        if [[ -z "${flags[*]}" && -n "${SSH_CONNECTION:-}" \
              && -z "${HERDR_ENV:-}${HC_TERMINAL_ID:-}${TMUX:-}${ZELLIJ:-}" ]]; then
            echo "switch: run this inside herdr (or tmux/zellij) on this box, not over plain ssh:" >&2
            echo "        a dropped connection would kill the switch half-done." >&2
            exit 1
        fi
        cmd=(nh os switch .)
    else
        cmd=(nh home switch -c jjmachan@linux .)
    fi
    echo "→ ${cmd[*]} ${flags[*]}"
    "${cmd[@]}" "${flags[@]}"

# Only flake.lock changes; `just switch` installs it.
[doc("Update inputs (`just update nixpkgs home-manager`), `all`, or list inputs and dates")]
update *targets:
    #!/usr/bin/env bash
    set -euo pipefail
    # name  date  rev, for every input of this flake (one level deep).
    inputs() {
        jq -r '.nodes as $n | $n.root.inputs | to_entries[]
            | ($n[.value].locked // {}) as $l
            | "\(.key)\t\($l.lastModified // 0 | todate | .[0:10])\t\(($l.rev // "-")[0:7])"' flake.lock
    }
    case "{{targets}}" in
        "")
            echo "Inputs and when each was last updated (flake.lock):"
            inputs | column -t -s $'\t'
            echo
            echo "Hand-pinned packages: herdr-core $(sed -n 's/^  version = "\(.*\)";/\1/p' pkgs/herdr-core/default.nix) (just update herdr-core)"
            exit 0 ;;
        herdr-core)
            have=$(sed -n 's/^  version = "\(.*\)";/\1/p' pkgs/herdr-core/default.nix)
            latest=$(curl -fsSL https://releases.herdr.dev/core/latest.json | jq -r .version)
            echo "herdr-core: pinned $have, latest release $latest"
            [[ "$have" == "$latest" ]] && exit 0
            echo "It isn't a flake input, so bump it by hand (docs/updating.md):"
            echo "  1. read what changed: https://github.com/herdrdev/herdr-core/blob/main/CHANGELOG.md"
            echo "  2. pkgs/herdr-core/default.nix: version = \"$latest\"; every hash = lib.fakeHash;"
            echo "  3. nix build .#herdr-core  → paste the 'got: sha256-…' hash, build again"
            echo "  4. the other platforms' hashes: https://releases.herdr.dev/core/$latest/manifest.json"
            echo "     (hex; convert with: nix hash convert --hash-algo sha256 --to sri <hex>)"
            exit 0 ;;
    esac
    before=$(inputs)
    if [[ "{{targets}}" == all ]]; then
        cmd=(nix flake update)
    else
        for t in {{targets}}; do
            printf '%s\n' "$before" | cut -f1 | grep -qx "$t" \
                || { echo "update: no input '$t'. Inputs: $(printf '%s\n' "$before" | cut -f1 | tr '\n' ' ')" >&2; exit 2; }
        done
        cmd=(nix flake update {{targets}})
    fi
    echo "→ ${cmd[*]}"
    "${cmd[@]}" 2>/dev/null
    changed=$(join -t $'\t' <(printf '%s\n' "$before" | sort) <(inputs | sort) \
        | awk -F'\t' '$3 != $5 { printf "  %-14s %s %s → %s %s\n", $1, $2, $3, $4, $5 }')
    if [[ -z "$changed" ]]; then echo "Already up to date."; exit 0; fi
    echo "Changed in flake.lock:"
    echo "$changed"
    echo "Next: just switch dry"

# Push the current branch to the same-named branch on the nixbox
sync:
    #!/usr/bin/env bash
    set -euo pipefail
    branch="$(git branch --show-current)"
    [[ -n "$branch" ]] || { echo "sync: detached HEAD, check out a branch first" >&2; exit 1; }
    # Only commits travel; refuse to leave uncommitted work behind silently.
    if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
        echo "sync: uncommitted changes, commit them first" >&2
        git status --short --untracked-files=no >&2
        exit 1
    fi
    git remote get-url nixbox >/dev/null 2>&1 || git remote add nixbox "{{nixbox}}:{{nixbox_repo}}"
    # Let a push to the branch checked out on the nixbox also update its files.
    # git still refuses if that working tree has uncommitted changes.
    ssh "{{nixbox}}" git -C "{{nixbox_repo}}" config receive.denyCurrentBranch updateInstead
    # The Mac owns these branches, so overwrite the nixbox's copy.
    git push --force-with-lease nixbox "$branch"
    echo "synced $branch → {{nixbox}}:~/{{nixbox_repo}}"

# Is the nixbox config in this checkout exactly what the nixbox is running?
check-nixbox:
    #!/usr/bin/env bash
    set -euo pipefail
    # Evaluating only computes the store path; nothing gets built.
    want="$({{nix}} eval --raw .#nixosConfigurations.nixbox.config.system.build.toplevel.outPath 2>/dev/null)"
    have="$(ssh "{{nixbox}}" readlink /run/current-system)"
    echo "config:  $want"
    echo "running: $have"
    if [[ "$want" == "$have" ]]; then
        echo "identical: switching would change nothing"
    else
        echo "differs: switching would change the nixbox"
        exit 1
    fi

# Brew formulae whose commands nix now also provides (candidates for `brew uninstall`)
brew-dupes:
    #!/usr/bin/env bash
    set -euo pipefail
    nixbin="$HOME/.nix-profile/bin"
    for formula in $(brew leaves); do
        for cmd in $(brew list --formula "$formula" | grep '/bin/' | xargs -n1 basename); do
            if [[ -e "$nixbin/$cmd" ]]; then
                echo "$formula  (nix has $cmd)"
                break
            fi
        done
    done
