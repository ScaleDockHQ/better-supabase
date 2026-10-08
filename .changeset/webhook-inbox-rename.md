---
"better-supabase": minor
---

`createInbox` in `better-supabase/blocks/jobs` is now `createWebhookInbox`, and its types are `WebhookInbox`, `WebhookInboxOptions`, `WebhookInboxEntry`, `WebhookInboxEvent`, `WebhookInboxMessage`, `WebhookInboxListOptions`, `WebhookInboxProcessOptions` and `WebhookInboxPurgeOptions`, matching the `webhook-inbox` SQL module. The old names stay as deprecated aliases for one minor; after that `createInbox` names the conversation inbox block.
