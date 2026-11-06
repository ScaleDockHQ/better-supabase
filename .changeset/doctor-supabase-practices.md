---
"better-supabase": minor
---

Doctor checks the app's own schema files against four Supabase and Postgres practices. BS365 warns about an update policy with no select policy, BS366 reports a policy that decides on `user_metadata`, BS367 warns about a view without `security_invoker`, and BS368 reports `timestamp` and `serial` columns.
