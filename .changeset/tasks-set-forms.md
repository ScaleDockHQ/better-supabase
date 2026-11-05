---
"better-supabase": minor
---

Adds `archive_tasks` and `delete_tasks`, the set forms of `archive_task` and `delete_task`. The client takes `tasks.archive({ workItemIds })` and `tasks.remove(workItemIds)`, checks access once per statement, writes once, and returns `{ ids, skipped }` with the ids that were refused. The tasks module moves to version 5; `better-supabase upgrade` renders the new functions.
