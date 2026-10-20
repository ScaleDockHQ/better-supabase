---
"better-supabase": minor
---

Doctor checks the migrations that haven't run for statements that lock a table with rows: an index built without `concurrently` (BS229), a foreign key or check added without `not valid` (BS230), a column type change or `set not null` without a validated check (BS231), a column added with a volatile default (BS232), a migration that takes an exclusive lock before `set lock_timeout` (BS233), and drops or renames (BS234, info). With `--db-url` it checks the migrations the database hasn't applied; offline, the ones after the new `doctor.migrationSafety.since` setting, or the newest one. `init` and `adopt` set `since` to the newest migration.
