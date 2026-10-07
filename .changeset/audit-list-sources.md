---
"better-supabase": minor
---

`createAuditLog().list()` and `export()` also filter by `source`, `actorKind` and `correlationId` (one value or a list), through the new `for_sources`, `for_actor_kinds` and `for_correlation_ids` arguments of `list_audit_events` and `count_audit_events`. An adopted log's `options.values` mapping applies to these filters too.
