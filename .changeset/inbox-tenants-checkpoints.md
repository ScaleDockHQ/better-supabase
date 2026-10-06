---
"better-supabase": minor
---

The webhook inbox serves per-tenant integrations: a message records a tenant (`tenantOf`, or the tenant `verify` returns), `inbox.list({ tenant })` and `inbox.purge({ tenant })` read and remove a tenant's messages, `message.checkpoint(fields)` saves progress a retry resumes from (`message.progress`), and `inbox.store(event)` stores an event a provider SDK already verified. The `webhook-inbox` module is at version 2: `receive_webhook` and `purge_webhooks` take a tenant, and `checkpoint_webhook` and `list_webhooks` are new; run `better-supabase sql upgrade`.
