---
"better-supabase": minor
---

Add `bsb.sessionHandle()` and `bsb.cached({ session })` to `better-supabase/next`. A page parks its verified session once, and each `'use cache: private'` island resolves it from the serializable handle without reading `cookies()` or `headers()`, verifying the token or building another PostgREST client. The verified-token memo now keys by a SHA-256 digest of the token instead of the token itself.
