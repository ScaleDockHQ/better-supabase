---
"better-supabase": minor
---

A write that breaks a `jsonb-schemas` JSON Schema now fails with a `validation` error whose `issues` say what is wrong (`"gold" is not one of ["free","pro"]`) and name the column in `path`, instead of a bare `check` error. The module adds a `better_supabase.check_json_schema()` trigger next to each CHECK constraint that raises `pg_jsonschema`'s validation errors; the constraint stays as the guarantee.
