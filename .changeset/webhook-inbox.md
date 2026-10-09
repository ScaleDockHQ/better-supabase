---
"better-supabase": minor
---

**Breaking:** `createInbox` in `better-supabase/blocks/jobs` is now `createWebhookInbox`, and its types are `WebhookInbox*`; the old names are removed. `better-supabase/blocks/inbox` has a different `createInbox` for the conversation inbox. Run `better-supabase sql upgrade`.

- Messages record a tenant and dedupe per source and tenant, and `message.checkpoint(fields)` saves progress a retry resumes from.
- `store(event)` stores an event an SDK already verified, and a source without secrets is store-only.
- Sources take `maxAttempts`, `process` takes `budgetMs` and renews leases, and bodies over `maxBodyBytes` (1 MiB) get a 413.
