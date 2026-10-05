#!/usr/bin/env bash
# open-popup.sh — the `new` action: open this plugin's prompt popup.
#
# Plugin actions run headless, so they cannot prompt. This one only asks herdr
# to open the `new-popup` pane entrypoint, which does get a terminal.

set -euo pipefail

die() { echo "worktrunk: $*" >&2; exit 1; }

socket="${HERDR_SOCKET_PATH:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr/herdr.sock}"
[[ -S "$socket" ]] || die "herdr socket not found at $socket"

plugin_id="${HERDR_PLUGIN_ID:-jjmachan.worktrunk}"

response="$(printf '%s\n' \
  "{\"id\":\"worktrunk-open\",\"method\":\"plugin.pane.open\",\"params\":{\"plugin_id\":\"$plugin_id\",\"entrypoint\":\"new-popup\",\"focus\":true}}" \
  | nc -U "$socket")" || die "could not reach herdr at $socket"

if jq -e 'has("error")' >/dev/null 2>&1 <<<"$response"; then
  die "could not open popup: $(jq -c '.error' <<<"$response")"
fi
