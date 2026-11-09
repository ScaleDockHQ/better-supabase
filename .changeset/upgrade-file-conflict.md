---
"better-supabase": minor
---

`upgrade` writes nothing when one block file was edited by hand, and the error includes the diff. `--force` overwrites that file and leaves the previous body at `.bak`. `--preserve <file>` leaves the hand edit and writes the new render beside it as `.new`.

An app table stays free of block grants when `database.sql.ownTablePolicies` is `"app"`.
