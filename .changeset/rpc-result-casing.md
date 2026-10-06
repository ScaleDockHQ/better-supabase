---
"better-supabase": minor
---

**Breaking for `casing: "camel"` projects and projects with codecs:** `db.$rpc` returns rows of a table (`returns setof customers`) and `returns table (...)` records in the configured casing, with the configured codecs applied, like repository reads. Before, it returned database names and raw wire values, so apps mapped the keys by hand. `gen` writes a `result` entry into the function metadata for functions whose rows decoding changes, and types their `Returns` as the model row (`Models["customers"]["Row"]`) or a record with app names. Scalars, `json` and `jsonb` results, and calls with another `schema`, are unchanged. The `returns` validator now runs on the decoded value, so a schema for the cased row works. Pass `{ raw: true }` to get what PostgREST sent, typed as `unknown`.

To upgrade, run `better-supabase gen`, then `better-supabase codemod 0.6`, which lists every `$rpc` call for review; delete the snake-to-camel mapping around their results, or add `{ raw: true }` where you need database names.
