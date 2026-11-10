# 0598: Read the audit log and the inbox through the passed filters, with capped counts

- Status: accepted
- Date: 2026-11-10

## Context

The performance audit seeded the local stack with 5.5M audit events (about 4.4M in one
organization, over 24 months) and 1M notification recipients (200,000 for one user), then timed
the reads as a signed-in member. Before the change:

| Read                                  | Before       |
| ------------------------------------- | ------------ |
| first audit page with a tenant        | 1.3 ms       |
| rare actor filter, tenant passed      | about 280 ms |
| rare event type filter, tenant passed | about 340 ms |
| search over the whole log, no match   | 4,200 ms     |
| search over 30 days, no match         | 340 ms       |
| `count_audit_events`                  | 630 ms       |
| `list_notifications`, default inbox   | 843 ms       |
| `notification_page`                   | 2,686 ms     |
| `notification_counts`                 | 219 ms       |

The notification reads used `case when ... (dismissed_at is not null) = dismissed` and
`param is null or` predicates. A security definer SQL function is planned without the argument
values, so none of them could use the partial inbox index and each call sorted the inbox.

## Decision

- `list_notifications` and `notification_page` become plpgsql that builds the where clause from
  the filters that were passed (as `list_audit_events` already did). `notification_page` also
  takes a keyset cursor, returns `hasMore` from a `limit + 1` read and caps its total at
  `total_cap` (default 10,000). `notification_counts` caps each count at `cap` (default 100).
- The audit log gets `(tenant, occurred_at, id)`, `(tenant, actor, occurred_at, id)` and
  `(tenant, event_type, occurred_at, id)` indexes. `list_audit_events` takes `entry_fields`,
  `count_audit_events` takes `cap`, and `get_audit_event` and `audit_event_types` are new. The
  event type list is a loose index scan per tenant.
- No trigram index on the search expression. A search over 30 days costs about 285 ms at 5.5M
  rows (about 7,000 entries a day); it grows with the window, not with the log. A GIN trigram
  index would add a write to every audit insert, so an app that needs faster search adds it
  to its own schema. Search always carries a window in the example.
- No `(user, tenant, created_at, id)` notification index. The seeded user belongs to one
  tenant, where the tenant condition filters nothing; revisit with a multi-tenant user.

## Alternatives considered

- Keep static SQL and rewrite the predicates: the inbox filters are optional, so the planner
  would still plan for every combination.
- An exact count with a cheaper plan: counting 200,000 rows costs time that no badge needs.

## Consequences

After the change (same data, same user):

| Read                                           | After  |
| ---------------------------------------------- | ------ |
| rare actor or event type filter, tenant passed | 0.3 ms |
| `count_audit_events` with `cap` 10,000         | 2 ms   |
| `audit_event_types` (40 types)                 | 13 ms  |
| `list_notifications`, default inbox            | 1 ms   |
| `notification_page` (capped total)             | 31 ms  |
| `notification_page` with unread filter         | 15 ms  |
| `notification_counts`                          | 1 ms   |
| `notification_counts` with actionable types    | 45 ms  |

`notification_page` stays above the 20 ms target because its capped total still reads 10,000
rows; a page that needs less passes a smaller `totalCap`. The actionable count of a badge reads
unresolved rows, which the unread index doesn't cover; an inbox with mostly resolved rows
would need a partial index on unresolved rows. A rare audit filter without a tenant still walks
the log (130 ms to 590 ms), so docs tell callers to pass the tenant.

Behavior changes: the page total and the badge counts are capped by default (changeset).
Partitioning the audit log, the purge rewrite and the app pages are not part of this change.
