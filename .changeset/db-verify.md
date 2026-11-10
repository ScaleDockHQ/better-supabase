---
"better-supabase": minor
---

`better-supabase db verify` reads row level security, grants, policies and definer `search_path` from the database, reports the findings and exits 1 on an error. `--write-tests` also writes the access matrix as one pgTAP file per persona.
