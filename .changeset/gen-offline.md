---
"better-supabase": minor
---

`better-supabase gen --offline` never connects: it reads `--snapshot <file>` or `source.snapshot` and fails with a usage error when neither exists, so `gen --check --offline` runs in CI without a database. It refuses `--db-url-stdin` and `--project-ref`.

`better-supabase upgrade` rewrites no module and no data migration is needed.
