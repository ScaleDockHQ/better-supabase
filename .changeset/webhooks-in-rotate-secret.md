---
"better-supabase": minor
---

`createIncomingWebhooks().rotateSecret(id, { grace })` and `rotate_incoming_webhook_secret(endpoint, grace)` replace an endpoint's signing secret without changing its token or URL. During `grace` the old secret still verifies Standard Webhooks and HMAC deliveries; `incoming_webhook_by_token` returns it as a new `previous_secret` column, so a module in custom mode needs that column. Rotating the token stays `rotate()`.
