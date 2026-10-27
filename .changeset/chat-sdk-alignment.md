---
"better-supabase": minor
---

The Chat SDK integration follows `chat` 4.42. Inbox thread ids name the inbox (`inbox:<inboxId>:<conversationId>`), so `channelIdFromThreadId` returns `inbox:<inboxId>`; build and read them with `inboxThreadId` and `decodeInboxThreadId`. The inbox module's upgrade (version 4 to 5) rewrites stored thread ids, subscriptions and thread state. `inboxAdapter` is an `Adapter<InboxThread, InboxMessage>`, forwards `WebhookOptions` (`waitUntil`, `propagateHandlerErrors`) from `dispatch` and `handleWebhook`, takes `concurrencyScope`, implements `markAsRead` and `fetchMessages` with `direction: "forward"` (through the new `after` argument of `list_inbox_messages`), and resolves reaction names to unicode. Adapter calls throw `ChatError` with the Chat SDK code (`RateLimitError` for `rate_limited` and `quota_exceeded`, `NotImplementedError` for `unsupported`) and the `DbError` as `cause`; `chatErrorOf` does the mapping. `inboundHandler` takes `propagateHandlerErrors`, `handler.mirror` records messages from other bots and skips only the bot's own, and `deliver` retries a platform `RATE_LIMITED` reply after `retryAfterMs` (`rateLimitRetries`, `maxRetryWaitMs`).

| 0.31                            | 0.32                                      |
| ------------------------------- | ----------------------------------------- |
| `inbox:<conversationId>`        | `inbox:<inboxId>:<conversationId>`        |
| `Adapter<string, InboxMessage>` | `Adapter<InboxThread, InboxMessage>`      |
| adapter errors are `DbError`s   | `ChatError` with the `DbError` as `cause` |
