---
"better-supabase": patch
---

App table write policies now refuse a read-only support or agent session. The insert, update and delete policies that `appTables` renders carry the same `actor_may_write()` check as every block policy, and the SQL defines the function when the file needs it. Run `upgrade` and generate a migration to pick it up.
