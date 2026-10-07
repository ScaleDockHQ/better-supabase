---
"better-supabase": minor
---

The SQL modules check tenant permissions in policies once per statement and fix several bugs in the SQL they generate.

- Policies call `tenant_ids_with()` instead of `can()` per row, and the subject checks of comments, attachments and incoming webhooks compare ids through the primary key.
- Recording usage needs the new `usage.record` permission (or the service role) instead of any membership. `record_usage` and `consume_quota` return `used` for the quota's period next to `today`, and `purge_usage_events(older_than, batch)` deletes old idempotency keys.
- The webhook inbox dedupes message ids per source and tenant, so two tenants of one provider can send the same id.
- `realtime.users` maps a table to its user column, so live queries on it use a per-user topic (`bs:t:<table>:u:<user id>`); pass `user` to `liveQuery` and `liveCount`, and the React hooks pass the signed-in user.
- `rotate_api_key` refuses an expired key, a managed audit log without `readPolicy` lists events for the service role only, and `purge_rate_limits` runs as `security definer` with each limit's own period.
- JSON-schema check names no longer collide, a table name with more than one dot is rejected, and CHECK constraints are re-added only when their expression changes.
- The audit trigger reads the JWT and request headers once per row, the audit list functions filter only on the arguments you pass, and per-tenant retention deletes tenant by tenant through the index.
- The table job backend, API keys, flags, notifications, outgoing webhooks, the outbox, comments, data exports, vector search and module hooks avoid per-row work and get the indexes they need. `tenant_ids_with_flag(key)` is the policy form of `flag_enabled`, and `track_events` skips updates that change nothing.
