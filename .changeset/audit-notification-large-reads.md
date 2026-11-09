---
"better-supabase": minor
---

The audit log and the notification inbox read in index order on logs of millions of rows. After `better-supabase upgrade` and a migration:

- `list_audit_events` takes `entry_fields` (`summary` leaves out the old and new record, `changed` and `metadata`), and `audit.list` takes `fields`. `count_audit_events` takes `cap`, and `audit.list` takes `countCap`. New: `get_audit_event` (`audit.get`) and `audit_event_types` (`audit.eventTypes`). The organization index gains the `id` tiebreaker, and the log gets `(tenant, actor, occurred_at, id)` and `(tenant, event_type, occurred_at, id)` indexes.
- `list_notifications` and `notification_page` add only the filters you pass, so the default inbox query reads the partial inbox index. `notification_page` takes `before`, `before_id` and `total_cap`, and returns `hasMore` and `totalCapped`.
- Behavior change: `notification_page` counts at most 10,000 matches (`totalCap: null` counts all), and `notification_counts` stops each count at 100 (`cap: null` counts all). Show "99+" for a capped badge.
