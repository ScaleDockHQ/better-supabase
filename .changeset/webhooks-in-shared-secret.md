---
"better-supabase": minor
---

Incoming webhook endpoints take `verify: "shared-secret"` for senders that cannot sign: the delivery carries the endpoint's secret in `signatureHeader` (`x-webhook-secret` by default), `receive` compares it in constant time, accepts the previous secret during a rotation grace and never stores that header. The module replaces the table's `verify` check constraint to allow the new mode.
