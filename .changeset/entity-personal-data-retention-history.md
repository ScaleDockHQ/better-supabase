---
"better-supabase": minor
---

An entity's manifest can now declare how it handles personal data, retention
and history. `EntitySurface` gains `subjectColumn`, `erase` (`delete`,
`anonymize` or `keep`), `legalHold`, `history` and `partition`.
`subjectAccessPlan(blocks)` and `subjectAccessRequest(lifecycle, input)` from
`better-supabase/blocks/data-lifecycle` read the declarations and return the
entities an access request collects and an erasure removes, blanks or keeps, so
an erasure never deletes append-only audit rows. `historyTabs(blocks)` from
`better-supabase/blocks/field-history` lists the entities that keep history.
`consent`, `data_subject_request` and `field_history` declare their personal
data, retention class and, for field history, a monthly partition. No schema
change.
