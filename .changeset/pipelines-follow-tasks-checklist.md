---
"better-supabase": minor
---

`pipelines`: a binding's `status.follow: true` moves a record to the first active stage whose category maps to a status written directly to its status column, so stage, history and time in stage stay right when app code writes the status (`PIPELINE_STAGE_INVALID` when no active stage matches a mapped status). `tasks`: `tables.checklist` can be `null` for an app with its own subtasks, which drops the checklist table and functions and returns `checklist: null`; `priority` takes `values` (the block's 0 to 4) for an app enum. Both render as before without the settings.
