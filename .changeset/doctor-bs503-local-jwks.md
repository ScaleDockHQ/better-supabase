---
"better-supabase": patch
---

`doctor` no longer reports BS503 for an exported `SUPABASE_JWKS` whose keys the
running stack's JWKS URL serves, such as the local public keys `env:local`
writes. Keys the stack does not serve are still reported.
