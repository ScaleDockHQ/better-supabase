---
"better-supabase": minor
---

The `zod()`, `valibot()` and `jsonSchema()` generators now describe each table: a title from the table name, a description from `comment on table`, field descriptions from `comment on column`, examples from `@example` lines in a column comment, and bounds (`minimum`, `maximum`, `minLength`, `maxLength` and the exclusive forms) from simple CHECK constraints such as `price >= 0` or `char_length(name) between 1 and 200`. The validators enforce the bounds, so a value the database would reject fails before the request. Run `better-supabase gen` to regenerate.
