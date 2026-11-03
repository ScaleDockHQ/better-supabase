---
"better-supabase": minor
---

Chat SDK webhooks can be received and processed in two steps, WhatsApp replies respect the 24-hour window, and the inbox broadcasts more. The `inbox` SQL module moves from version 8 to 9, so run `better-supabase upgrade`.

- New `chatWebhookPipeline({ chat, receiveChat, adapter, inbox, retry })` returns `{ receive, process }`. `process` replays with `deduplicate: false` and `propagateHandlerErrors: true`, so a handler error fails the queue job; it throws a `TypeError` when both Chat instances share a state prefix.
- `inboundHandler` takes `deduplicate` (`"first-attempt"` by default, `"always"`, `"never"`), `interactive`, `actions` and `onAction`. `ChatInboundEvent` gets `attempt` and `ChatWebhookResult` gets `retryIn`. A webhook-inbox handler may return `{ retryIn }` to pick the retry delay.
- Inbound events get a `processing` status, an `available_at` backoff and a lease; a stale lease is picked up again.
- New `sendWithinWindowOrTemplate` and `ChatWindowClosedError` (`CHAT_WINDOW_CLOSED`), and `whatsappInteractiveOf` for button, list and quick replies. Conversations get `lastInboundAt` and `activeStreamId`; deliveries get `deliveredAt`, `readAt` and `failedAt`.
- New `conversations.setActiveStream({ conversationId, streamId })`, the `INBOX_STREAM_ACTIVE` error, the `event.created` broadcast and the `realtimeColumns` option. `Topic.trigger` takes `columns`.
