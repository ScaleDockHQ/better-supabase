---
"better-supabase": patch
---

The `workflow-sdk-world` SQL module follows `@workflow/world-postgres` 5.0.4: its DDL adds the `seq_in_band` column to `workflow.workflow_event_slots`, from the `0026_add_seq_in_band` migration.
