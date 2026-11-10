---
"better-supabase": minor
---

Doctor BS629 reports a migration that drops a `when '<entity>' then` arm the schema file still dispatches, and an `import_apply_batch` that omits an entity from `blocks.imports.options.targets`. `import_entities()` returns the entities the imports module dispatches, so an override can call the list instead of copying it.

`better-supabase upgrade` rewrites the imports module. The next schema migration adds `import_entities`.
