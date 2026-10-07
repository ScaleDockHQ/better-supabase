---
"better-supabase": minor
---

`createSafeFetch(options)` in `better-supabase/blocks/webhooks` returns a `fetch` for URLs users or tenants supply: it applies `publicUrl` (HTTPS only, no credentials, public addresses only, or your `allowUrl`), checks every redirect before following it, drops credentials on a redirect to another origin, and times out. A refused URL throws `UnsafeUrlError`.
