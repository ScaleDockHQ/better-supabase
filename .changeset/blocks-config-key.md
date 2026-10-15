---
"better-supabase": minor
---

Blocks are configured under a top-level `blocks` key in `better-supabase.config.ts`, the foundation blocks (`tenant`, `access`, `updated-at`, `ensure-rls`, ...) included. `sql.modules` is removed; `sql` keeps the SQL-wide settings (`workflow`, `dir`, `prefix`, `testsDir`, `schema`, `api`). The resolved config carries `blocks` and `blockNames`, `sql add` edits `blocks`, and `schemas/config-v1.json` describes the new key. The config types are renamed to match: `BlocksConfig`, `BlockConfig`, `AccessBlockConfig` and `BlockMode`.
