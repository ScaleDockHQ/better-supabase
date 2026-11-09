---
"better-supabase": minor
---

An import target can declare `refs`, a map from a field on `item.refs` to the entity that field points at. The batch resolves every such key in one query and passes the subject ids to the write as `resolved`. A key with no import record adds the warning `IMPORT_REF_MISSING`.
