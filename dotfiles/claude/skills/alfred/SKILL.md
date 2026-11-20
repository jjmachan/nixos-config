---
name: alfred
description: Send Slack messages as Alfred, jjmachan's work Slack bot. Use whenever you would message jjmachan or anyone in Slack (DM jjmachan, ping them when a task finishes or you need them, post or reply in a channel). Never post as jjmachan.
---

# Alfred

Alfred is jjmachan's bot in the work Slack. Everything you send to Slack goes
out as Alfred, through the `alfred` command. The claude.ai Slack connector acts
as jjmachan: use it only to **read** (search, read channels, threads and
profiles). Its posting tools are denied in settings.

## Sending

```sh
alfred dm "Build is green; PR #42 is ready for review."      # to jjmachan
alfred post C0123ABCD "Deploy of api v2.3 finished."         # to a channel
alfred post C0123ABCD --thread 1763600000.123456 "Follow-up" # reply in a thread
```

- The text is Markdown (headings, **bold**, lists, `code`, links). For long or
  multi-line text, pipe it in instead of quoting:
  `alfred dm <<'EOF' … EOF`.
- Output is `channel=… ts=…` and a permalink. Keep the `ts` to reply in the
  same thread later, and give jjmachan the permalink when it helps.
- Channels: pass the ID (`C…`, `G…`). Find it with the Slack connector
  (`slack_search_channels`). `#name` works only for public channels.
- `not_in_channel`: Alfred has to be invited to that channel first. Tell
  jjmachan; don't fall back to posting as jjmachan.
- `no token`: Alfred isn't set up on this machine. Tell jjmachan to run
  `alfred login`.

## Reading replies

jjmachan is in their DM with Alfred, so the connector can read it as them: use
`slack_read_thread` (or `slack_read_channel`) with the `channel` and `ts` that
`alfred` printed.

## How Alfred writes

Short and plain, like a good assistant's note: lead with what happened or what
you need, then the details. Say which machine or repo the message is about when
it isn't obvious. Don't post to channels other people read unless jjmachan
asked you to.
