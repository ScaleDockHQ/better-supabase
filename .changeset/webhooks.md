---
"better-supabase": minor
---

The `webhooks-in` module and `createIncomingWebhooks` in `better-supabase/blocks/webhooks` give each tenant trigger URLs with hashed tokens, and `createSafeFetch` calls URLs that users supply.

- Endpoints verify Standard Webhooks, HMAC-SHA256 or a shared secret, with size and rate limits, keep secrets in Vault, and hand deliveries to the webhook inbox. `update`, `rotate` and `rotateSecret(id, { grace })` change them, and `options.subjects` attaches them to a record.
- `verifyWebhook` and incoming endpoints accept Svix's `svix-*` headers.
- `createSafeFetch(options)` allows public HTTPS URLs only, checks every redirect, drops credentials on a redirect to another origin, and throws `UnsafeUrlError` for a refused URL and `UrlCheckError` for a failed check such as DNS.
