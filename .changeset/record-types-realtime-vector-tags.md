---
"better-supabase": minor
---

`better-supabase codemod table-tags` moves `recordTypes`, `realtime` tables and `vectorSearch` entries into `@bsb subject`, `@bsb realtime` and `@bsb vector-search` tags when the config read through the tag gives the same value, and lists hand-written `better_supabase.broadcast_topic()` triggers. The `subject` tag gains `held`, `template` and `read-access`. See ADR 1204.
