---
"better-supabase": minor
---

`db backfill` changes the elements of a jsonb array with `--array <path> --match <json>` and `--delete` or `--merge <json>`. It runs in `ctid` batches, and `--dry-run` prints the number of rows and elements it would change. Doctor adds BS240 for a migration that renames or removes an enum value (`alter type ... rename value`, `delete from pg_enum`), and the `db` docs describe how to remove a value through a new type.
