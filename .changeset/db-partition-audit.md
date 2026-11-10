---
"better-supabase": minor
---

`better-supabase db partition audit` moves an audit log created before `options.partitioned` onto monthly partitions without stopping writes. It calls the generated `convert_audit_log_to_partitioned` procedure, which copies in committed batches and swaps the tables under one short lock. Pass `--batch-size`, `--drop-old` or `--dry-run`.
