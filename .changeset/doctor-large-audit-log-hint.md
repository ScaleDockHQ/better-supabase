---
"better-supabase": patch
---

`doctor` reports `BS399` (info) when `better_supabase.audit_events` is still a plain table with an estimated one million rows or more, and names `blocks.audit.options.partitioned` and `convert_audit_log_to_partitioned()`. It needs a database; saved snapshots skip it.
