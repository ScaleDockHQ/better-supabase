---
"better-supabase": minor
---

With `blocks.audit.options.partitioned` on, `upgrade` writes `better_supabase.convert_audit_log_to_partitioned(batch_size, drop_old)`. Call it as the service role, outside a transaction block, to move an existing audit log onto monthly partitions while it keeps taking writes. It copies in committed batches, takes a short lock that blocks writes but not reads for the last rows and the swap, and keeps the old table as `audit_events_unpartitioned`.
