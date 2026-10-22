---
"better-supabase": minor
---

Add the `forecasts` block (`better-supabase/blocks/forecasts`). `createForecasts({ transport })` snapshots the deals forecast for a period and currency with `snapshot()`, keeps a copy of the deals behind each number, and lists, opens and compares snapshots with `list()`, `get()` and `changes()`, which labels each deal added, removed, won, lost or changed. Every snapshot writes `forecast.snapshotted`, and the block adds the `forecasts.read` and `forecasts.snapshot` permissions.

Add the `field-history` block (`better-supabase/blocks/field-history`). Name the database columns to track per subject type in its `subjects` option, and a trigger records each change with the old and new value, the author and the time. `createFieldHistory({ transport }).of(subject)` reads a record's changes, newest first, for members with `history.read` and read access to the record.
