---
"better-supabase": minor
---

Inbox handlers can tell their last attempt. `createInbox` takes `maxAttempts` per source (8 by default), stored with each message as it arrives, and `InboxMessage` and `InboxEntry` carry `maxAttempts` next to `attempts`. The `webhook-inbox` module moves to version 3: `receive_webhook` takes `max_attempts` as a seventh argument (`better-supabase sql upgrade` drops the six-argument signature), and `claim_webhooks` marks a message whose lease ran out on its last attempt as dead instead of claiming it again.
