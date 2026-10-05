---
"better-supabase": minor
---

The CLI reads `supabase/config.toml` from `--cwd` or the nearest parent directory that has one, like the Supabase CLI, and stops at the directory that holds `.git`. In a monorepo package, the local database port for `gen` and `snapshot`, doctor's `config.toml` checks, schemas and migrations, the SQL kit's `schema_paths` check, `seed` and `keys` now use the `supabase` directory at the repository root; `keys` writes `signing_keys.json` there by default.
