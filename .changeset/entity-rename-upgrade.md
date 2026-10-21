---
"better-supabase": minor
---

`sql upgrade` renames an installed block's tables when you change `blocks.<name>.entities`, instead of refusing the change.

- It compares the module SQL under the installed names (from the `@bs-entities` line) and the new ones, and writes guarded renames for tables, columns, indexes, policies, triggers and functions, so the rows stay. Permission keys in a role and permission catalog and stored `subject_type` values move to the new names too. Each statement checks the old name first, so a second run changes nothing.
- `sql upgrade --check` reports `<block> has entity renames to apply to its tables`, and its JSON `data` gains `renames` when there are any.
- Number sequence keys, recorded outbox events and your own hook functions keep their names; rename those yourself.
- SQL modules can declare a renamed table or column in `NAMES.migrations`. `sql upgrade` renders the rename after your table and entity renames.
- `entityRenameChanges` is removed from `better-supabase/sql`. Use `entityRenamePlan(names, installedModules, installedSql, layout)`, which returns the rename steps and the modules it can't pair up.
