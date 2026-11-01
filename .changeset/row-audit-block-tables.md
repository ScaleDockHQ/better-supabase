---
"better-supabase": minor
---

Block tables write audit row entries through deferred row triggers, and a row that a block function already recorded in the same transaction appears once. `blocks.audit.options.blockTables` (`"entities"`, `"all"` or `"none"`) sets the scope, and `better-supabase table enable audit` writes the registration into your schema file. Run `better-supabase upgrade` and generate a migration.
