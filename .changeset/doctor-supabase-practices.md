---
"better-supabase": minor
---

Doctor checks the app's own schema files against four Supabase and Postgres practices. BS365 warns about an update policy with no select policy, BS366 reports a policy that decides on `user_metadata`, BS367 warns about a view without `security_invoker`, and BS368 reports `timestamp` and `serial` columns.

Doctor BS383 warns about a storage insert policy without select and update policies, BS384 about a policy that calls `auth.uid()`, `auth.jwt()` or `auth.role()` outside `(select ...)`, and BS385 about a policy column no index starts with. On a database on your machine, doctor reads `supabase db advisors` when the Supabase CLI is 2.81.3 or later and falls back to splinter otherwise. Token verification requires the audience `authenticated` unless `auth.audience` is set.
