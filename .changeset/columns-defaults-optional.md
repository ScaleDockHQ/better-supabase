---
"better-supabase": minor
---

The `fields` schema that `gen` builds from a block's `columns` (and `columnsSchema`) no longer
requires a `not null` column that has a `default` on input, so a create that leaves
`risk text not null default 'low'` or a `metadata` column to its default passes validation. The
column is still required on output, and an explicit `null` is still refused. `columnsSchema` now
returns `StandardSchemaV1<ColumnsInput<C>, ColumnsOutput<C>>`, and `ColumnsInput` is exported from
`better-supabase/blocks`.
