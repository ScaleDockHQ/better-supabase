---
"better-supabase": minor
---

Make codegen extensions safer to write and to change.

- Generators can declare `apiVersion: 1`, and `gen` refuses a version it doesn't know. The first-party generators declare it.
- Generators receive `model`: the tables and enums `gen` emitted, with the TypeScript type it wrote for each column. Code that builds a `GeneratorInput` by hand now needs a `model`; `testGenerator` builds one from `meta`.
- `gen` deletes files an earlier run wrote and this one no longer writes, and `gen --check` reports them.
- `gen` warns about `tables` and `json` keys that match no table or json column.
- `gen --watch` reloads the config file when it changes and regenerates.
- The introspection cache key includes the typegen version, the cache file is written atomically, and the catalog fingerprint covers the dependencies of RLS policies.
- `better-supabase config` prints the resolved config, with the database password redacted.
