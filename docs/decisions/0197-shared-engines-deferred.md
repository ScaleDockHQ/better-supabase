# 0197: Shared engines for recurrence, periods, money and digests are planned, not shipped

- Status: proposed
- Date: 2026-11-01

## Context

The seeds and business engines plan names five shared engines: an RFC 5545
recurrence expander on Temporal (`rrule_occurrences` in SQL), period and
lifecycle helpers, money and digest helpers with consent checks, vertical glue
between blocks, and Postgres features (pg_cron schedules and similar).

## Decision

None of the five engines ships with the seeds change (ADR 0196). Each is a
public API and needs its own docs page, example, exports entry and baselines
(architecture invariant 9), and a half-built engine without a consumer would
fail Knip. They move to their own changes, in this order: recurrence, periods
and lifecycle, money and digest, vertical glue, Postgres features.

## Alternatives considered

Shipping an unexported expander with tests: no consumer, so Knip rejects it and
it would rot.

## Consequences

Maintenance plans, appointments and calendar alarms keep their own recurrence
handling until the shared expander exists. Revisit when a second block needs
the same rule.

## Periods engine (feat/engine-periods)

The `periods` block ships with this change: the `periods` table, `period_for`,
`period_is_open`, `lock_period`, `close_period`, `reopen_period` and the close
protocol where a block contributes `blockers` and `onClose` functions through
`contributes.periods`. Accounting contributes `fiscal_period` and leave
contributes `leave_year`. The existing `close_accounting_period` and
`close_leave_year` keep their names.

### Deferred

- Payroll runs, usage billing windows and forecast snapshots do not contribute a
  kind yet. Each needs a range to row mapping of its own, and none of them has a
  second consumer to shape it. They add a kind with `contributes.periods`.
- `finance.closeMonth` and `leave.rolloverYear` did not exist, so nothing
  converts to a wrapper. Closing a fiscal period or a leave year stays on
  `closeAccountingPeriod` and `closeYear`, and `periods.close` calls the same SQL.
- Blocks do not check `period_is_open` before they write. Accounting still
  refuses posts into closed fiscal periods by its own status, and leave has no
  write guard for a closed year. Adding the guard per block is the follow-up.
