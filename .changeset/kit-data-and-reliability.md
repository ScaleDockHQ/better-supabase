---
"better-supabase": minor
---

The SQL kit's rows and role settings, which a schema diff can't capture, move to `supabase/better-supabase-data`, and the new `better-supabase sql data` writes them into a migration stamped after the newest one. `rate-limit` sets `pgrst.db_pre_request` that way, and doctor BS313 warns when the live database never calls `check_request()`. `sql upgrade` writes next to the located `config.toml`, and each module rejects options it doesn't declare.

Breaking: `entitlements` no longer defaults `entitlements.customer` to `organizations.stripe_customer_id`. It reads the managed `organizations` module's column when that module is installed; otherwise `sql add` stops until you set it. `tenant_ids_with_entitlement(key)` gives policies a set check.

Jobs enforce max attempts at claim, retry with full jitter and replay dead letters (`replay_dead_job`, `jobs.replay`). The outbox orders by `(xid, position)` and gives events uuid ids. Outgoing webhooks take a lease token, follow the Svix retry schedule with `Retry-After`, and disable a destination after failing for `disableAfter`. Notifications back off between deliveries and fail them after `max_attempts`. Key indexes lead with the key, webhook policies read `tenant_ids_with()` once per statement, `jsonb-schemas` adds its checks `not valid` and validates them separately, and `purge_rate_limits()`, `purge_webhook_deliveries()` and `purge_notifications()` join the other purges.
