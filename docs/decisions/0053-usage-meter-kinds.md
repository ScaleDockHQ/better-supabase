# 0053: Usage meters have a kind: counter, distinct or computed

- Status: accepted
- Date: 2026-10-20

## Context

The usage module counts recorded quantities. Active users per month and
storage in bytes are not sums of increments: the first needs one unit per
subject and period, the second is a gauge another table already knows. Apps
worked around this with their own tables and lost quotas and Stripe reporting.

## Decision

`options.meters.<meter>.kind` is `counter` (default), `distinct` or
`computed`. A distinct meter adds `usage_distinct` and `track_usage`, which
inserts the subject for the period and records one unit on the first sight. A
computed meter has a `query` of `(tenant, value)` rows and `usage_refresh`
sets today's counter so the period total equals the value, scheduled hourly
with pg_cron when present. Both write the counters table, so quotas and
`reportUsageToStripe` need no change. The query is rejected when it holds `;`
or `$$` and is not exposed by `usage_meters()`.

## Alternatives considered

Separate gauge tables with their own quota functions duplicated the window
logic. A view per computed meter could not be summed over a period.

## Consequences

Computed values between refreshes are stale, and a gauge reported across days
shows as a period total only through the counters. Only inline catalogs can
declare kinds. Revisit if table catalogs need them.
