---
"better-supabase": minor
---

`better_supabase.importing()` returns true while the transaction runs in an import session, so an app trigger or function can skip a side effect during an import with `if not better_supabase.importing() then ... end if;`. A user session always gets false.

`better-supabase upgrade` rewrites the prelude and the next schema migration creates one function. No data migration is needed.
