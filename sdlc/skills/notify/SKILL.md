---
name: notify
description: Publish a notification to the cluster's ntfy bus through the broker — when unattended work finishes, fails, or needs a decision. Triggers "notify me", "ping me", "send a notification".
metadata: {"nanobot":{"requires":{"bins":["curl"]}}}
---

# Notify

The bus is the cluster's one notification path: host unit failures, Prometheus
and Flux alerts, and this agent all publish to it, and the phone and the laptop
subscribe. Use it when the chat channel is not the answer — a cron run that
finishes while nobody is looking, a long task that fails, a decision that
blocks further work.

## The one call

| Purpose | Broker path |
|---|---|
| publish to the agent's topic | `$BROKER_URL/notify/agent` |

```sh
curl -sS --max-time 20 -X POST \
  "$BROKER_URL/notify/agent?title=Weekly%20review&priority=default&tags=robot" \
  --data-binary 'Three commits proposed; one needs a human.'
```

- `POST` only; the broker refuses every other method.
- The path is the topic and nothing else (`^/[a-z0-9_-]{1,64}$`). The query
  string passes through untouched, so `title`, `priority` and `tags` are the
  only knobs and they are all optional.
- `title` becomes a header upstream: keep it ASCII, one line, under ~100
  characters. Without one the notification shows the topic.
- `priority`: `min`, `low`, `default`, `high`, `urgent`. `high` for a failure
  or a blocked decision, `default` for a finished run, `low` for a reminder.
- `tags` is a comma-separated list of short words (`robot`,
  `white_check_mark`); the client renders them as an icon or emoji.
- The body is the message. The broker caps it at 4096 bytes: truncate a long
  report and say where the rest is, rather than losing the tail to a 413.
- Send no `Authorization` header. The broker injects the `agent` user's token,
  and that user holds `agent:wo` only — `POST /notify/alerts` is a 403, so the
  agent cannot page.

## When not to

- The user is in the chat: the reply is the notification. Never double-send.
- Progress on a task the user is watching.
- Anything that repeats: one message per outcome, not per step. A loop that
  notifies on every iteration is a page storm.

## Failure

`404 unknown_logical_host` and `503 credential_unavailable` are the broker's:
report the code and stop, do not retry another spelling. A `403` is either the
broker refusing the method or the bus refusing the topic — `/notify/alerts` is
the second, because the `agent` user holds `agent:wo` and nothing else. `413`
means the body was over 4096 bytes. `429` is the bus's rate limiter: wait, and
do not retry in a loop. A notification that fails is not a reason to fail the
work that produced it — say so in the reply and move on.
