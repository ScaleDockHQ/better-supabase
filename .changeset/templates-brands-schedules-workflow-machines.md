---
"better-supabase": minor
---

Templates take brand starters: with `blocks.templates.options.brand` set to the table and column that hold a tenant's brand, a starter `sync` saves with a `brand` reaches every organization of that brand. `templates.recurring` applies a template at each occurrence of a recurrence rule kept in reminders: `upsert`, `list` and `remove` manage schedules, `recurring.schedule()` (a manifest schedule every five minutes) enqueues one `templates.recur` job per occurrence on the `jobs` client, and `recurring.job` applies it once. A state-machine machine with `workflow: "<slug>"` reads its stages and edges from the published workflow-editor version and pins that version per record. Timelines add `transition` entries from the status history and `message` entries from the record's conversation.

Breaking: `TemplateScope` adds `"brand"`, `ActivitySource` adds `"transition"` and `"message"`, and `StatusState` adds `workflow` and `workflowVersionId`, so exhaustive switches over them need the new cases. Nothing is renamed. Run `better-supabase upgrade` and `db diff` to add the `brand` column, the schedule tables (with `reminders`) and the lifecycle's `workflow_version_id`.
