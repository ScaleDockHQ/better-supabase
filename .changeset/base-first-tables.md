---
"better-supabase": minor
---

A block creates its table under its own names and your schema files extend it with `alter table`, and the generated `fields` now carry the columns you add for every block, memberships included. Tag an app table that keeps its names with `comment on table ... is '@bsb block-table=<block>.<table>'` and each mapped column with `@bsb column=<column>` instead of writing `tables` and `columns` entries; an entry in the config still wins. `better-supabase codemod adopt-names --table <block>.<table>` renames one table to the block's names: it writes a rename migration, rewrites the statements in your schema files that name the table, removes the `tables` and `columns` entries and lists the types that change. See ADR 1190 and the [0.82 to 0.83 guide](https://bettersupabase.com/docs/migration/0.82-to-0.83).
