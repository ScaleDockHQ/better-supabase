---
"better-supabase": patch
---

`diffAppTables` marks every change that rows already in the table may not pass as breaking, with steps: a new `unique` column or unique set, a removed option, a raised `min` or lowered `max`, a checked format, a new reference target, a new scope, and removing `timestamps`, `rank` or `softDelete`. These get their own kinds (`column.unique`, `column.options`, `column.bounds`, `column.format`, `column.reference`, `table.scope`, `table.unique`, `table.columns`). Indexes, comments, the subject and `onDelete` stay safe.

`apply` compares the whole design with `appTables`. It reports the tables the design leaves out as kept (`data.kept`), and it refuses a table or column rename without `--allow-breaking`. With the flag it prints the `alter table ... rename` statements to run before `sql sync` (`data.renames` under `--json`).
