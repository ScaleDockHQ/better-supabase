---
"better-supabase": minor
---

The `audit`, `webhook-inbox` and `jobs` SQL kit modules add `purge_audit_log`, `purge_webhooks` and `purge_job_archive`. Each deletes rows older than an interval in batches and returns how many it deleted, for nightly pg_cron jobs. Only `service_role` can execute them. Run `better-supabase sql add` again to update the kit files.
