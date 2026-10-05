#!/usr/bin/env bash
# new-worktree.sh — pick or name a branch, create its worktree with worktrunk,
# and open it as a new tab in the current herdr workspace.
#
# Runs as a herdr plugin popup pane (placement = "popup"), so it has a terminal
# and closes when it exits. Bound to prefix+shift+g via the `new` action.
#
# Standalone use, for testing outside herdr:
#   HERDR_WORKSPACE_ID=w8 WORKTRUNK_REPO=~/path/to/repo bash new-worktree.sh
#   WORKTRUNK_DRY_RUN=1 …            # print the commands instead of running them
#
# worktrunk decides where the worktree goes: it applies the per-project
# worktree-path template from ~/.config/worktrunk/config.toml, so the result
# matches the sibling layout the repo already uses (main.feat-harborize, …).

set -euo pipefail

die() { printf '\nworktrunk: %s\n' "$*" >&2; sleep 3; exit 1; }
run() { if [[ -n "${WORKTRUNK_DRY_RUN:-}" ]]; then printf '  DRY RUN: %s\n' "$*"; else "$@"; fi; }

for tool in wt jq git fzf; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is required but not installed"
done

herdr_bin="${HERDR_BIN_PATH:-herdr}"

# ── Which repo are we in? ───────────────────────────────────────────────
# A popup gets no HERDR_PANE_ID by design; the invoking pane is in the
# context JSON instead.
repo="${WORKTRUNK_REPO:-}"
if [[ -z "$repo" && -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ]]; then
  # Context keys are flat: focused_pane_cwd, workspace_cwd, workspace_id, …
  repo="$(jq -r '
    (.focused_pane_cwd // .workspace_cwd // empty)
  ' <<<"$HERDR_PLUGIN_CONTEXT_JSON" 2>/dev/null || true)"
fi
[[ -n "$repo" && "$repo" != "null" ]] || repo="$PWD"

git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 \
  || die "not inside a git repository: $repo"

# Work from the repo root so wt resolves the right project config.
repo="$(git -C "$repo" rev-parse --show-toplevel)"

# ── Default base branch: origin/HEAD, else main, else master ────────────
default_branch="$(git -C "$repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
if [[ -z "$default_branch" ]]; then
  for candidate in main master; do
    if git -C "$repo" show-ref --verify --quiet "refs/heads/$candidate"; then
      default_branch="$candidate"
      break
    fi
  done
fi
default_branch="${default_branch:-main}"

# ── Branch rows: existing branches, marked with whether they already have
#    a worktree. Deduped by branch, preferring the worktree entry.
branch_rows() {
  wt list -C "$repo" --branches --format json 2>/dev/null | jq -r '
    def color(c): "\u001b[" + c + "m";
    def reset: "\u001b[0m";

    # Top-level array only: each entry also nests a `remote` object with its
    # own `branch` key, so a recursive walk would double-count.
    [ .[] | select(.branch != null)
          | { branch: .branch,
              has_wt: (.kind == "worktree"),
              is_current: (.is_current == true) } ]
    | sort_by((.has_wt | not), .branch)   # parens: | binds looser than ,
    | .[]
    | (if .has_wt then color("32") + "●" + reset else color("90") + "·" + reset end)
      + " " + (.branch | .[0:38])
      + (if .has_wt then "  " + color("90") + "worktree" + reset else "" end)
      + (if .is_current then "  " + color("36") + "current" + reset else "" end)
      + "\t" + .branch
  '
}

# pick_branch <prompt> <header> [initial query]
# Prints "<existing>\t<branch>" where <existing> is 1 when the branch came from
# the list and 0 when it was typed. Prints nothing when cancelled.
#
# It runs in a command substitution, so it cannot set variables or exit for the
# caller — everything it needs to say has to go through stdout.
pick_branch() {
  local prompt="$1" header="$2" query="${3:-}" out rc line1 line2

  set +e
  out="$(branch_rows | fzf \
    --ansi \
    --delimiter='\t' \
    --with-nth=1 \
    --print-query \
    --query="$query" \
    --prompt="$prompt" \
    --header="$header" \
    --height=100% \
    --info=inline \
    --no-multi)"
  rc=$?
  set -e

  # 130 = cancelled with esc/ctrl-c. 0 = picked a row. 1 = no match, query only.
  [[ $rc -eq 130 ]] && return 0

  line1="$(sed -n '1p' <<<"$out")"
  line2="$(sed -n '2p' <<<"$out")"

  if [[ -n "$line2" ]]; then
    printf '1\t%s' "${line2##*$'\t'}"
  elif [[ -n "${line1// }" ]]; then
    printf '0\t%s' "$line1"
  fi
}

# ── Which branch? ───────────────────────────────────────────────────────
picked="$(pick_branch 'branch > ' 'type a new branch name, or pick an existing one   ● has a worktree')"
[[ -n "$picked" ]] || exit 0
existing_branch="${picked%%$'\t'*}"
branch="${picked#*$'\t'}"
[[ -n "${branch// }" ]] || exit 0

# ── Which base? Only asked when the branch is new. ──────────────────────
base=""
if [[ "$existing_branch" == "0" ]]; then
  picked="$(pick_branch 'base > ' "new branch ${branch} will start from this" "$default_branch")"
  [[ -n "$picked" ]] || exit 0
  base="${picked#*$'\t'}"
  base="${base:-$default_branch}"
fi

# ── Create (or just check out) the worktree ─────────────────────────────
# --no-cd: no shell integration in this process. -y: no approval prompts.
if [[ "$existing_branch" == "1" ]]; then
  printf '\n  opening \033[1m%s\033[0m …\n' "$branch"
  run wt switch --no-cd -y -C "$repo" "$branch" || die "wt switch failed"
else
  printf '\n  creating \033[1m%s\033[0m off %s …\n' "$branch" "$base"
  run wt switch --no-cd -y -C "$repo" --create "$branch" --base "$base" \
    || die "wt switch failed"
fi

if [[ -n "${WORKTRUNK_DRY_RUN:-}" ]]; then
  printf '  DRY RUN: would look up the worktree path and open a tab\n'
  exit 0
fi

# ── Where did it land? ──────────────────────────────────────────────────
path="$(wt list -C "$repo" --format json 2>/dev/null \
  | jq -r --arg b "$branch" '
      [ .[] | select(.branch == $b and .kind == "worktree") | .path ] | first // empty
    ')"
[[ -n "$path" && -d "$path" ]] || die "no worktree path found for $branch"

# ── Open it as a tab in this workspace ──────────────────────────────────
workspace_id="${HERDR_WORKSPACE_ID:-}"
if [[ -z "$workspace_id" && -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ]]; then
  workspace_id="$(jq -r '.workspace_id // empty' <<<"$HERDR_PLUGIN_CONTEXT_JSON" 2>/dev/null || true)"
fi

args=(tab create --cwd "$path" --label "$branch" --focus)
[[ -n "$workspace_id" ]] && args+=(--workspace "$workspace_id")

response="$("$herdr_bin" "${args[@]}")" || die "could not create the tab"
if jq -e 'has("error")' >/dev/null 2>&1 <<<"$response"; then
  die "herdr rejected the tab: $(jq -c '.error' <<<"$response")"
fi

printf '  \033[32m✓\033[0m %s\n' "${path/#$HOME/\~}"
sleep 1
