---
"better-supabase": minor
---

An import run now indexes search once per record when it closes. While a run
writes through `import_upsert_batch`, the search triggers note each record in
`better_supabase.import_search_dirty`, and `finish_import_run` or
`cancel_import_run` indexes the noted records through the new
`search_refresh_run`. A record that several batches of one run change is
indexed once; it becomes searchable when the run closes.

`recordTypes.<type>.search.statement: true` indexes a record type through
statement triggers (`bsb_search_<type>_insert`, `_update`, `_delete`) instead of
the row trigger, so a set-based write fires one search call per statement.
Switching a type renames its triggers: run `better-supabase upgrade` and
generate a migration.

A batch import target now receives `subjectId` on each item, as documented.
Before, an update batch inserted duplicates and fell back to one `write` per
item.

Run `better-supabase upgrade` (search 4, imports 3).
