---
"better-supabase": minor
---

Import conflicts, errors and warnings are stored on `import_run_issues`. A later run that applies the same key sets `resolved_at`. `list_import_runs` includes open issue counts. `list_import_issues` pages one run, with the total capped at 10,000. `resolve_import_conflict` takes `keep`, which adopts the database stamp as the baseline, or `overwrite`, which clears the stamp and owned hash so the next batch can write the source.

`better-supabase upgrade` rewrites the imports module. The next schema migration adds `import_run_issues` and the two functions.
