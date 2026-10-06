---
"better-supabase": minor
---

`gen` keeps a column that a CHECK makes not null optional on insert when the table has a row-level `before insert` trigger, which can fill it before the CHECK runs. The row type stays not null. For any other not-null column the database fills on insert, list its database name in `tables.<table>.insertOptional`: `InsertOf`, the insert validators and the metadata's `hasDefault` then treat it as optional. `gen` fails on a name that is not a column of the table.
