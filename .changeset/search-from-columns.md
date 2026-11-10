---
"better-supabase": minor
---

A subject's `search` takes `columns` next to `from`: the columns of the record's own table the source view reads. The indexing trigger then fires on an update of those columns only, instead of every update. The `drive_node` subject sets `["name"]`, so a move, a size change or a lock no longer re-indexes a file. Run `better-supabase upgrade` and generate the migration.
