---
"better-supabase": minor
---

Opt in to nullable to-one includes under row level security. With `relations: { nullableUnderRls: true }` in the config, `gen` types a to-one relation as nullable when the related table has RLS, even over a `not null` foreign key, since a policy can hide the related row and PostgREST then returns `null`. An include with `required: true` is now typed non-null for any to-one relation, because it drops parents without the related row. The option defaults to `false`, so generated types only change when you turn it on.
