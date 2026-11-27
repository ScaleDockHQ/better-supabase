---
"better-supabase": patch
---

`codemod naming` no longer renames objects the library does not own. Its migration leaves alone a policy that your schema files create, such as PermDock's `better_supabase_*_read_only_actors` policies, and the unnamed check of a column that your files add to a block table, such as `flags_kind_check`. Before, renaming those made the next schema diff drop and recreate them. The codemod also rewrites calls to renamed SQL functions through `api.<name>(` in SQL and pgTAP files, and through `rpc/<name>` paths in TypeScript.
