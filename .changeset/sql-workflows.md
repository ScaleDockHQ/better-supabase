---
"better-supabase": minor
---

The SQL modules support three workflows through the new `sql.workflow` config key: `pg-delta` (Declarative Schemas 2.0, the default), `migra` (declarative schemas 1.0 with `supabase db diff`) and `migrations`. When the key is unset, the CLI reads `supabase/config.toml` and keeps a project that already uses migra on migra. Under `migrations`, `sql add`, `sql sync` and `sql upgrade` write the modules into one `<stamp>_better_supabase_modules.sql` migration instead of `supabase/schemas`, `gen` writes the read sets into a migration, and doctor compares against the newest module migration. `better-supabase init --workflow <name>` picks the workflow, and `sql add` and `sql sync` turn pg-delta on in `config.toml` under the pg-delta workflow. Doctor BS316 stays silent when the config chooses `migra` or `migrations`, and the BS404 grant hint names a new migration under `migrations`.
