---
"better-supabase": patch
---

The Postgres executor (`better-supabase/postgres`) now sends values for `json` and `jsonb` columns as JSON text in inserts, updates and upserts. Arrays, arrays of objects and plain strings failed before with `invalid input syntax for type json`, because node-postgres sends a JavaScript array as a Postgres array literal. A string is stored as a JSON string, as it is over PostgREST, `null` stays SQL `null`, and each element of a `jsonb[]` column is encoded the same way. Postgres array columns such as `text[]` still receive arrays. Comparison filters (`eq`, `neq`, `gt`, `gte`, `lt`, `lte`) on a `json` column send an array or object operand as JSON text too.
