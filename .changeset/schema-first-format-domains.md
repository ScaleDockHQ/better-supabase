---
"better-supabase": minor
---

`migrate schema-first`, `init --preset` and `add --preset` type a format column (`email`, `url`, `rating`, `percent`) as a domain in the `bsb` schema, such as `bsb.email`, and write the domains as files under `supabase/schemas/bsb`. A column with its own `min`, `max` or `options` keeps its inline check. Rollups and lookups are written as `security_invoker` views in `public/views`. `gen` types a domain column as its base type.
