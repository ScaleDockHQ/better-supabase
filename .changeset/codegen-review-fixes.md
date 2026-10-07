---
"better-supabase": minor
---

`gen` fails with both names when two columns become the same app name (`user_id` and `userId`), when tables in two schemas generate the same model key, or when two generated exports share a name. Unique keys leave out an index's `INCLUDE` columns, table grants come from `aclexplode` so a read-only introspection role sees them, enum and CHECK exports are valid identifiers, an enum outside `public` whose name repeats another schema's gets the schema as a prefix, and `toCamel` keeps a leading underscore. `tables`, `json` and `functions` config keys accept `schema.table` (and `schema.table.column` for `json`); a bare key that matches more than one schema warns. A view gets Insert and Update validators only when it has a writable column.

Doctor reports BS222 when an `int8` identity or sequence column, or a `numeric` column, decodes as `number`, which loses precision past `Number.MAX_SAFE_INTEGER`; set `codecs.int8` to `"string"` or `"bigint"`, or `codecs.numeric` to `"string"`, to keep it exact.

`gen` reuses `database.types.ts` while the snapshot, typegen options and versions are unchanged, the catalog fingerprint ignores temporary tables, and generated docs look up columns through an index instead of scanning the catalog for every table.
