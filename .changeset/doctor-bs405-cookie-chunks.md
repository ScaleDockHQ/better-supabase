---
"better-supabase": patch
---

BS405 names the estimated cookie chunks when the token's claims pass the limit, because the session cookie is split at 3,180 bytes and 50 memberships already need 4. Doctor output changes only in that message; `upgrade` rewrites no module and no data migration is needed.
