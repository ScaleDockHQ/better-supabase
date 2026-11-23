---
"better-supabase": minor
---

`codemod config --prune` and doctor now remove more entries that equal a default: `callbacks` entries that keep the hook's name, `api` entries, `tables` and `columns` entries that keep the block's default name, `on` entries the schema's foreign keys give and the `idType`, `table` and `cascade` of a record type. Each is removed only when a render without it gives the same files. See ADR 1186 and the [0.82 to 0.83 guide](https://bettersupabase.com/docs/migration/0.82-to-0.83).
