---
"better-supabase": minor
---

App tables take `rollups` and `lookups` (ADR 0044). A rollup counts, sums or takes the minimum, maximum or average of a column of another app table that references this one, optionally only for the rows whose select column equals one option. A lookup reads a column of the row a reference points at. Both are structured keys, so a design never carries SQL, and `resolveConfig` lists the valid tables and columns when a key is wrong.

`sql sync` writes `public.<table>_view` with `security_invoker = true`, so each rollup counts only the rows the caller can read. Only `authenticated` and `service_role` can read the view. The pgTAP file checks that the view runs as the invoker and shows a stranger no rows. `gen` reads it as a read-only model (`db.projectsView.findMany()`).

A design with rollups or lookups writes design format 3. `diffAppTables` reports a change to them as the safe `table.computed`. Create shows rollups and lookups as computed rows on the table and edits them in a Computed section of the table inspector.

`better-supabase/config` exports `APP_ROLLUP_AGGREGATES` and the `AppRollupConfig`, `AppRollupAggregate` and `AppLookupConfig` types.
