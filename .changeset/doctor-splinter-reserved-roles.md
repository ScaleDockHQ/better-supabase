---
"better-supabase": minor
---

`better-supabase doctor` reports each problem once. BS207 (overlapping permissive policies) and BS216 (unindexed foreign keys) skip the tables Supabase's performance advisor (BS200) already reports, and still run in full when BS200 is off, skipped or fails. The advisor lints are fetched once per category per run.

The new BS319 check (error) flags SQL that alters, drops or changes the membership of a role Supabase reserves (`supabase_admin`, `supabase_auth_admin`, `pgbouncer` and the others), with the file and line. For the Data API roles (`authenticator`, `anon`, `authenticated`, `service_role`) only `alter role ... set` and `reset` are allowed.
