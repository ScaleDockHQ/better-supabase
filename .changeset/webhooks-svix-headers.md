---
"better-supabase": minor
---

`verifyWebhook` accepts the `svix-id`, `svix-timestamp` and `svix-signature` header names that Svix-based senders use, next to the Standard Webhooks `webhook-*` names. A request without `webhook-id` is verified from the `svix-` set, so `createInbox({ secrets })` and incoming endpoints with `standard-webhooks` verification take both. Incoming endpoints also deduplicate on `svix-id`.
