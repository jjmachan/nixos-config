# Run from the Mac. Sync is one-way: Mac → nixos, never the other way.

nixos := "jjmachan@nixos"
nixos_repo := "workspace/personal/nixos-config"
# Flakes stay off in /etc/nix/nix.conf on the Mac, so turn them on per call.
nix := "nix --extra-experimental-features 'nix-command flakes'"

# List recipes
default:
    @just --list

# Push the current branch to the same-named branch on nixos
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
    git remote get-url nixos >/dev/null 2>&1 || git remote add nixos "{{nixos}}:{{nixos_repo}}"
    # Let a push to the branch checked out on nixos also update its files.
    # git still refuses if that working tree has uncommitted changes.
    ssh "{{nixos}}" git -C "{{nixos_repo}}" config receive.denyCurrentBranch updateInstead
    # The Mac owns these branches, so overwrite nixos's copy.
    git push --force-with-lease nixos "$branch"
    echo "synced $branch → {{nixos}}:~/{{nixos_repo}}"

# Is the nixbox config in this checkout exactly what nixos is running?
check-nixbox:
    #!/usr/bin/env bash
    set -euo pipefail
    # Evaluating only computes the store path; nothing gets built.
    want="$({{nix}} eval --raw .#nixosConfigurations.nixbox.config.system.build.toplevel.outPath 2>/dev/null)"
    have="$(ssh "{{nixos}}" readlink /run/current-system)"
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
