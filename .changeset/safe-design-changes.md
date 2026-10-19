---
"better-supabase": minor
---

`diffAppTables` and `diffDesigns` from `better-supabase/preset` list what changes between two sets of app tables. Added tables and optional columns are safe. A dropped or renamed table or column, a type change (of a column or of the table's id) and a column made required without a default are breaking, and each comes with its expand-and-contract steps.

`apply --preset` with a design now lists the breaking changes to tables the config already has, writes nothing and exits 1. Pass `--allow-breaking` to write them anyway; `--dry-run` shows them without it.

Doctor gains BS228 (warning): a column of an app table whose type or nullability in the database differs from `appTables`.

Create shows the changes since the page loaded its link on a Changes tab in Get code.

Migration: a script that runs `apply --preset` with a design that retypes, drops or renames app table columns now needs `--allow-breaking`.
