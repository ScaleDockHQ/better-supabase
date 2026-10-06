---
"better-supabase": minor
---

New `webhooks-in` SQL module and `createIncomingWebhooks` in `better-supabase/blocks/webhooks`: per-tenant trigger URLs with hashed tokens, optional Standard Webhooks or HMAC-SHA256 verification, a body size limit, a per-endpoint rate limit, receive counters and the last status. Deliveries go to the webhook inbox with the endpoint's tenant, for processing with retries.
