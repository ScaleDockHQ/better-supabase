---
"better-supabase": patch
---

Check more SQL at `gen` time, with the module or config key in the error:

- `gen` renders the installed modules and parses each one with the Postgres reader. A module that renders SQL Postgres rejects stops `gen` with the module name, the file position and the statement.
- Config SQL is checked for every key that holds SQL, not only `authorization.functions` and event payload `{ sql }` columns: the role sources' and platform roles' `through.where`, persona and fixture role `setup`, `vectorSearch` `boost`, `predicate` and `order`, and `realtime.triggers` payload `{ sql }` values. The error names the config path.
