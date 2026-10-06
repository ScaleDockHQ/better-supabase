---
"better-supabase": minor
---

pg-delta (Declarative Schemas 2.0) is now the default diff engine. `better-supabase init` adds `[experimental.pgdelta] enabled = true` to an existing `supabase/config.toml` that has no such table, and leaves a table that sets `enabled = false` as it is. Doctor adds BS316, a warning for projects that keep declarative schemas or `sql.modules` on the legacy migra engine, with the steps to switch. `doctor --fix-grants` output from `hookGrantBlock()` now assumes pg-delta when no engine is passed, and the docs move the migra commands into a legacy section.
