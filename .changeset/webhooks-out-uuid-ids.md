---
"better-supabase": patch
---

`sql.modules.webhooks-out.options.eventIdType` and `runIdType` accept `uuid` in managed mode. Only types other than `text` and `uuid` are migration-only now, so doctor BS314 no longer flags a managed module that keeps uuid event or run ids.
