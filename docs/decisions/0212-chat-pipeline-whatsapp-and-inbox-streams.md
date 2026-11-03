# 0212: Split Chat SDK webhooks into receive and process, and add WhatsApp windows and inbox streams

- Status: accepted
- Date: 2026-11-03

## Context

`inboundHandler` stored a webhook and replayed it into Chat SDK in the same
request. A handler that failed lost the event once Chat SDK's duplicate
check had seen it, the inbound store had no lease, and the replay could not
tell a first delivery from a retry. WhatsApp also needed its reply window,
template fallback and interactive replies, and the inbox needed to tell
subscribers which stream is writing a reply.

## Decision

`chatWebhookPipeline` returns `{ receive, process }`. `receive` runs a
handler-less Chat on its own state prefix (`chat-sdk:receive`) and stores the
verified request. `process` replays it with `deduplicate: false` and
`propagateHandlerErrors: true`, so a handler error fails the queue job. The
pipeline throws a `TypeError` when both Chat instances share a state prefix.
`inboundHandler` takes `deduplicate` (default `"first-attempt"`),
`ChatInboundEvent` carries `attempt`, and a queue handler may return
`{ retryIn }`.

The `inbox` SQL module moves to version 9. Inbound events get a `processing`
status, an `available_at` backoff and a `locked_until` lease, so attempts
count when processing starts and a stale lease is picked up again.
Conversations get `last_inbound_at` and `active_stream_id`, deliveries get
`delivered_at`, `read_at` and `failed_at`, and `set_active_stream` claims or
releases a stream. `sendWithinWindowOrTemplate` and `whatsappInteractiveOf`
live in `better-supabase/chat-sdk`; `@chat-adapter/whatsapp` is an optional
peer typed structurally. `Topic.trigger` takes `columns`, and the inbox takes
`realtimeColumns` and broadcasts `event.created`.

## Alternatives considered

Deduplicating in `process` with our own table was rejected because Chat SDK's
state already does it. A queue `permanent` result needs a dead status in
`fail_webhook`, which is a separate webhook-inbox version, so it is not part
of this decision.

## Consequences

A failing handler retries through the queue instead of being dropped. Apps
need a second state prefix and a handler-less Chat. The `sendTemplate`
signature of the WhatsApp adapter is typed from its documented shape and
needs a check against the installed release. Revisit when the webhook inbox
gets a dead result.
