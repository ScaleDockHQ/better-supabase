---
"better-supabase": patch
---

Adds the JWT matrix bench (`pnpm --filter better-supabase bench:jwt`) and records its findings: the access token hook stays under 32 ms at 500 memberships, while the `memberships` claim grows 95 bytes per membership (27 cookie chunks at 500). The package ships no new runtime code, `upgrade` rewrites no module and no data migration is needed.
