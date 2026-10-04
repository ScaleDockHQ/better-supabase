---
"better-supabase": minor
---

Breaking: the SQL kit follows one naming standard. Run `better-supabase sql upgrade`, then `sql sync` and `sql data`; the [0.4 to 0.5 guide](https://bettersupabase.com/docs/migration/0.4-to-0.5) lists every step. The forward steps rename `memberships.org_id` and `invitations.org_id` to `organization_id`, `better_supabase.audit_log` to `audit_events` (with `occurred_at` and `organization_id`, and a read-only `audit_log` view until 0.6), and `audit_trigger()` to `audit_row_change()`. Doctor reports the old column names in your SQL (BS309), also when a column is unqualified next to its table.

The modules new in this release use the same names: `webhook_endpoints` with `event_types` and the statuses `pending`, `delivering`, `succeeded`, `retrying`, `dead` and `canceled`; notifications with `type`, `data`, `actor_id` and `user_id`, and `types` instead of `kinds` in `createNotifications`. Permission keys follow `<area>.<verb>`, and managed tables get `updated_at` triggers and indexes on their foreign keys.

Breaking: `toCloudEvents` and `kitCloudEvent` put the actor in `data.actorId` instead of the `actorid` context attribute, so user ids stay out of broker headers. The outbox relay prefixes event types with `dev.better-supabase`, and `webhooks.sink()` removes the prefix again.
