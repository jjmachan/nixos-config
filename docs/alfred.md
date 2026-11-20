# Alfred

Alfred is a bot in the work Slack. Claude Code sessions, on the Mac and on the
nixbox, send Slack messages as Alfred rather than as jjmachan: a ping when a
task finishes, a question, a post in a channel.

Alfred used to be a hermes-agent in its own MicroVM (retired 2026-11-12; see
`hosts/nixbox/agents/default.nix`). Its Slack app lives on; now it's only an
identity that local agents post through.

## Pieces

| Where | What | Set up by |
| ----- | ---- | --------- |
| Slack | The Alfred app and its bot token (`xoxb-…`) | By hand, at api.slack.com/apps |
| Both | `alfred` CLI in `~/.local/bin` | `dotfiles/bin/alfred`, via the dev module |
| Both | The `alfred` Claude Code skill in `~/.claude/skills/alfred` | `dotfiles/claude/skills/alfred`, via the dev module |
| Both | Bot token and your member ID | Once per machine, by hand: `alfred login` |
| Both | Deny rules for the Slack connector's posting tools | By hand, in `~/.claude/settings.json` (not managed by Nix) |

```text
Claude Code session
  ├─ alfred skill ──> alfred dm / alfred post ──> Slack API, bot token ──> posts as Alfred
  └─ claude.ai Slack connector (acts as jjmachan) ──> read-only: search, read DMs and threads
```

## The token

Copy the **Bot User OAuth Token** from the Alfred app's *OAuth & Permissions*
page (reinstall the app if it has none). `alfred login` checks it with Slack
and stores it; it reads the token from stdin, so nothing has to be pasted into
a hidden prompt:

```sh
# On the Mac, with the token on the clipboard:
pbpaste | alfred login U06LQUAFX1R

# The nixbox, from the Mac's Keychain:
security find-generic-password -s alfred-slack -w | ssh nixbox '~/.local/bin/alfred login U06LQUAFX1R'

alfred whoami    # Alfred in <workspace>
```

Run with no input, it prompts instead (the token is hidden as you type or
paste). The argument is your member ID, the target of `alfred dm`.

The Mac keeps it in the Keychain (service `alfred-slack`); the nixbox in
`~/.config/alfred/token`, mode 0600. Your member ID, the target of
`alfred dm`, goes in `~/.config/alfred/dm-user`. Neither is in this repo: it's
public.

Scopes: `chat:write` is enough for DMs and channels Alfred has been invited to.
Add `chat:write.public` to post in public channels without an invite.

## Not posting as you

The claude.ai Slack connector acts as you. Its posting tools are denied in
`~/.claude/settings.json` on both machines, so an agent can still read Slack as
you but can only send as Alfred:

```json
"deny": [
  "mcp__claude_ai_Slack__slack_send_message",
  "mcp__claude_ai_Slack__slack_send_message_draft",
  "mcp__claude_ai_Slack__slack_schedule_message",
  "mcp__claude_ai_Slack__slack_add_reaction",
  "mcp__claude_ai_Slack__slack_create_canvas",
  "mcp__claude_ai_Slack__slack_update_canvas",
  "mcp__claude_ai_Slack__slack_create_conversation"
]
```

Other connectors that reach Slack (Composio, if its Slack toolkit is
connected) aren't covered by these rules.

## Replies

Alfred only sends. When you answer in your DM with Alfred, an agent reads the
reply as you, through the connector, with the `channel` and `ts` that
`alfred` printed.
