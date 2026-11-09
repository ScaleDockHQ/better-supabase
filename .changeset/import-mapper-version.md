---
"better-supabase": minor
---

An import run records the version of its mapping code (`runs.start({ mapperVersion })`, `ImportRun.mapperVersion`). `reapply_import_records(tenant, source, mapper_version, entity?)` makes the next run rewrite the records an older version wrote, and `export_import_hashes(tenant, source, entity?)` lists the record map's hashes.

`better-supabase upgrade` rewrites the `imports` module and the next schema migration adds one column and two functions. No data migration is needed.
