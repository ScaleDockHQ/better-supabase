---
"better-supabase": patch
---

`gen` makes the `column` and `sequenceColumn` of each `number-sequences` entity optional on insert, so adopters no longer list them in `tables.<table>.insertOptional`.
