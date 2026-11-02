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

## Shipped: recurrence and maintenance

The recurrence engine and the maintenance engine shipped on `feat/engine-maintenance`.

- Recurrence: `better-supabase/recurrence` (`expandRule`, `rruleOccurrences`) and the
  `recurrence` SQL module (`rrule_occurrences`, `rrule_next`). Calendar, tasks, reminders and
  templates expand through it, `calendar_rule_starts` wraps the SQL function, and a
  conformance test compares the TypeScript and SQL instants.
- Maintenance: the `housekeeping` SQL module (`maintenance()`, `maintenance_jobs`,
  `maintenance_schedule()`, `maintenance_scheduler()`) and a `housekeeping` contribution that
  `approvals`, `trash`, `webhook-inbox`, `rate-limit`, `idempotency` and `chat-sdk-state`
  use. The old purge and expire functions keep their names.

### Deferred (recurrence and maintenance)

- Recurrence: bookings series, shifts and maintenance plans keep their own date arithmetic.
  Maintenance plans use `everyDays` intervals rather than RRULE, so they move only when plans
  take a calendar rule. The templates SQL function `due_template_occurrences` exists, but the
  TypeScript client still expands schedules itself and skips unreadable rules, while
  `rruleOccurrences` treats an unreadable rule as one occurrence. Moving the client onto the
  SQL function needs that difference decided first.
- Maintenance: the fallback that runs `maintenance()` from the `block_ticks` queue when pg_cron
  is missing is not wired. Without pg_cron the app calls `maintenance()` from a cron route.
  There is no doctor finding yet for "jobs are due and no scheduler runs"; it needs a live
  database check, which doctor only makes for the advisors. The other modules with purge
  functions (`audit-retention`, `queue` archive, `workflow-sdk`, `support`, `usage-kinds`,
  `webhooks-out`, `notifications-delivery`) still need their own schedule.
- Docs examples: both engines have a docs page with an inline example. A runnable app under
  `apps/examples` is not added.
