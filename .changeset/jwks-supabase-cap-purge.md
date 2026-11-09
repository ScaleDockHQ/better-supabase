---
"better-supabase": minor
---

The JWKS cache of a Supabase Auth key set (`/auth/v1/.well-known/jwks.json`) is capped at 600 seconds, whatever `cacheSeconds` says, and `purgeKeys(url?)` from `better-supabase/server` forgets a key set (or every set and imported secret) after you revoke a signing key. An unknown `kid` still refetches once per 30 second cooldown. `upgrade` rewrites no module and no data migration is needed.
