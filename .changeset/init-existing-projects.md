---
"better-supabase": minor
---

`better-supabase init` recognizes a project that already has a `supabase` folder: it prints the migrations, schema files and snapshot tables it found, says that the database is unchanged, and points at `doctor` and `table` as next steps. The new `--from` flag starts a project from a `postgres://` URL, which writes the database's schema to `supabase/snapshot.json`, or from a preset, design code, URL or file like `--preset`.
