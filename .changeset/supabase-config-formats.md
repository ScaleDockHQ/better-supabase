---
"better-supabase": minor
---

The CLI reads and writes `supabase/config.toml`, `config.json` and `config.jsonc` through one module that follows the Supabase CLI 3.2.0 preference order, reports a json and jsonc conflict, and keeps comments when `better-supabase` edits a key. `jsonc-parser` is inlined into the CLI build, so apps install nothing new.
