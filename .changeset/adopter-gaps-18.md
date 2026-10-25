---
"better-supabase": minor
---

Adopting existing app tables with blocks:

- `database.sql.tenantColumn` names the tenant column of every block table, such as `organization_id`, instead of `tenant_id`. Explicit `blocks.<name>.columns.<table>.tenant` mappings still win, a name another column of a block table has is refused, and `gen` writes the name to the block's `names` so its TypeScript client reads rows back with `tenant_id`.
- The line tables of `quotes`, `invoices` and `deals` (`quote_lines`, `invoice_lines`, `deal_lines`) can be the app's own tables, mapped through `tables.lines` and `columns.lines`. The new `options.lineExtraColumns` adds columns to the line table that each line's `fields` writes and that line reads return under `fields`.
- `defineSupabase(schema, { temporal }).blocks(...)` passes `temporal` to every block instance it builds.
- `db.$apiResult(fn, args)` calls an API schema function like `db.$api` and returns a `Result` with a `DbError`, like a repository call. `db.$api` is unchanged.
- Record types (`config.records` keys, `blocks.<name>.on` keys) may contain hyphens, such as `purchase-order`, in every block. Subject type columns and checks accept them, and triggers named after a type use underscores (`bsb_field_history_purchase_order`), so two types that differ only by `-` and `_` are refused. Doctor BS346 no longer reports a hyphenated type that `config.records` registers.
