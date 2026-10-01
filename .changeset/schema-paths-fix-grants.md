---
"better-supabase": minor
---

Doctor reads the declarative schemas in `[db.migrations] schema_paths` order, then the files no entry matches, then the migrations newest first, and the built-in `config.toml` parser reads arrays over several lines. `sql add` names the kit files no `schema_paths` entry matches, because `supabase db diff` would skip them. `doctor --fix-grants` prints the grant and revoke SQL BS404 asks for as one block to append to the migration `supabase db diff` wrote. For PermDock's hook, BS404 points to `permdock supabase hook generate --grants-out` instead, and when a `-- permdock:grants v1` migration already grants the function, it says to apply the migrations.
