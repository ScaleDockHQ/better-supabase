---
"better-supabase": patch
---

`better-supabase introspect --snapshot <file>` now converts a saved snapshot without connecting to a database, and rejects `--snapshot` next to `--db-url-stdin` or `--project-ref` with a usage error.
