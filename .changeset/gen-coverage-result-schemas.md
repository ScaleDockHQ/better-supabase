---
"better-supabase": minor
---

`gen` no longer turns a column type it does not know into `string`. The column stays `unknown`, and `gen` prints one notice naming those columns. Composite types become nested objects in the zod, valibot, JSON Schema and Standard Schema output, a domain column uses its base type (including `not null` and simple `VALUE` checks), and `geometry` and `geography` validate as JSON. A `returns table` function gets a result schema from its columns.

`better-supabase/result-schema` exports `resultSchema(readSet)` and `specResultSchema(meta, spec)`. Each returns a Standard Schema of the composed read, built from the columns the query selects. Unknown keys are dropped unless you pass `unknownKeys: "reject"`. A record binding stays unchecked until `registerRpcReturn` names a schema for it.
