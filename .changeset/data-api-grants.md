---
'better-supabase': minor
---

Data API grants. Supabase no longer grants new tables to `anon` and
`authenticated` (new projects since May 30, 2026, existing projects from
October 30, 2026). Declare what each role reaches in the new `expose` config,
write the grants with `better-supabase sql add grants`, and let doctor report
missing grants as BS106 (it also notes `[api] auto_expose_new_tables = false`).
`permission denied for table` errors are still `forbidden`, and their `hint`
now points at `expose`.
