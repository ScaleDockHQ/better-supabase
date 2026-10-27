---
"better-supabase": patch
---

The Supabase World follows `@workflow/world` and `@workflow/world-postgres` 5.0.5: every timestamp in the `workflow` schema is `timestamptz`. The `workflow-sdk` block (version 4) converts an older install once under a lock on the World's tables, and moves the values `now()` wrote from the session's time zone to the instant they recorded (set `workflow.legacy_timezone` when the World's pool ran outside the database's zone). The run mirror, `workflow_open_hooks`, `workflow_purge_runs` and the World's `analytics` read the columns as they are. Run `better-supabase upgrade` and apply the migration before you deploy this release.
