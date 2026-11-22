---
"better-supabase": minor
---

Optional features of a block over your own table follow the columns the table declares, not a column entry in the config. Declaring `start_part` and `end_part` on your leave requests table turns the parts of the day on, and a `confidential` column on your leave types turns confidential leave on; the entries `columns.requests.startPart`, `endPart` and `columns.types.confidential` are only for other names. Declaring one part column without the other is an error. A block never adds an optional column to a table you own, so BS622 reports required columns only, and `codemod config --prune` also removes a `null` for an optional column your table lacks. A column entry on a block's own table no longer raises an error; the entry does nothing. See ADR 1184 and the [0.82 to 0.83 guide](https://bettersupabase.com/docs/migration/0.82-to-0.83).
