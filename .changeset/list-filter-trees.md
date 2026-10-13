---
"better-supabase": minor
---

Add `filters` to `defineListQuery`: an allow-list of typed fields that a ReUI Filters `FilterQuery` tree may name. `parse` checks each rule's operator and value against the field type, caps depth and rule count, drops unfinished rules, and takes a `timeZone` that relative dates resolve in. The tree compiles to repository `where` input, so it runs through PostgREST, the Postgres executor and SQLite. `filterFields(labels)` returns ReUI `FilterField` objects, the URL keeps the tree in one base64url `filter` parameter that `toSearchParams` and the nuqs parsers handle, and `openapi` and `jsonSchema` describe it.
