---
"better-supabase": minor
---

Close the gaps CentraKit hit while adopting better-supabase:

- Support sessions work with an app-owned request context, and the proxy prunes stale cookie chunks and takes an auth-outage hook.
- `createJobs`, `createIdempotency` and `withLease` accept a block transport (`rpcTransport`), so job stats, dead jobs, retries, idempotency keys and leases work through the `sql.modules.<name>.api` wrappers without a direct Postgres connection.
- Jobs, idempotency, rate limits, outgoing webhooks and usage get TypeScript `purge` methods and `purgeJob` handlers for the `purge_*` functions; `purgeAuditLog` and the webhook inbox purge accept a transport.
- Behaviour change: `cancel_organization_deletion` asks the access contract for the `cancelDelete` permission (`organization.delete` by default) through the new `member_can_while_deleting()`, instead of hard-coding the `owner` role. With the default roles nothing changes; with an authorization provider, any member the provider grants the key can cancel. An access module in `custom` mode keeps the owner check.
- Attachments take `subjects.<type>.permissions` (`read`, `upload`, `manage`), and attachments and comments take `subjects.<type>.scope`: a scope the authorization provider declares, so a grant on the subject record counts next to one on the tenant. Comments' `readableBy` also takes `{ sql, enforce: true }`, which applies it to the read policy.
- The `realtime-tables` module adds `better_supabase.broadcast_topic()`, a row trigger that fills a topic's `{column}` placeholders from the row and sends the change. `topic.trigger(table, options)` returns the `create trigger` statement, and `realtime.triggers` makes `sql sync` write them next to the topic policies.
