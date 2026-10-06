---
"better-supabase": minor
---

`gen` types a nullable column as not null when a CHECK constraint requires it: `check (slug is not null)`, or an `is not null` term of a top-level `and` (`check (kind = 'x' and owner_id is not null)`). The row type, `UpdateOf`, the validators and the metadata drop `| null`, and `InsertOf` makes the column required unless it has a default. Terms under `or` or `not`, and `not valid` constraints, change nothing. This tightens the generated types of such columns; code that compared them with `null` may now report an unnecessary check.
