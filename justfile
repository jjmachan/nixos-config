# Run from the Mac. Sync is one-way: Mac → nixos, never the other way.

nixos := "jjmachan@nixos"
nixos_repo := "workspace/personal/nixos-config"

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
    # The Mac owns these branches, so overwrite nixos's copy. git still refuses
    # to touch whatever branch is checked out over there (e.g. main).
    git push --force-with-lease nixos "$branch"
    echo "synced $branch → {{nixos}}:~/{{nixos_repo}}"
