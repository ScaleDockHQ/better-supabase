---
"better-supabase": patch
---

`blocks.audit.options.subjectColumns.<column>.tables` with an `id` key, such as `{ "public.jobs": "id" }`, falls back to the entry's `record_id`. With `restricted: true` the log keeps no row data, so `job_id` stayed null on the jobs table's own entries. Run `better-supabase upgrade` and generate a migration to rewrite the generated column.
