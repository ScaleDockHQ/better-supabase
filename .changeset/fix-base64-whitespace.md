---
"better-supabase": patch
---

`fromBase64` removes ASCII whitespace before it computes the padding, so Postgres `encode(..., 'base64')` output wrapped every 76 characters decodes.
