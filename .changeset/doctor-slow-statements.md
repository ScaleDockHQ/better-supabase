---
"better-supabase": minor
---

`doctor` warns with BS732 about statements that `authenticated`, `anon` and `service_role` ran at least 5 times with a mean of 100 ms or more, read from `pg_stat_statements` (and from `pg_stat_user_functions` when `track_functions` is on). It reports nothing when the extension is not installed.
