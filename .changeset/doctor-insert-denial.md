---
"better-supabase": minor
---

Doctor BS107 counts a restrictive `with check (false)` policy as the denial of insert for a tenant table. An insert policy has no `using`, so the rule could not be satisfied for insert before.
