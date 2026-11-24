---
"better-supabase": patch
---

`doctor` runs without a database. When none runs and none is configured, the
checks that read the schema use the saved snapshot (`source.snapshot`, else
`supabase/snapshot.json` from `gen --save-snapshot`) and doctor says so on
stderr. When the run includes checks that need the database itself, such as
the advisors or BS208, the error names them so you can leave them out with
`--ignore` or `--only`.
