---
"better-supabase": patch
---

The HMAC and HS256 helpers type their imported keys from `crypto.subtle` instead of the global `CryptoKey`, so the published types check under `@types/node` 24 without the DOM lib.
