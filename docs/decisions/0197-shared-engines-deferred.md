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

## Deferred: money engine (feat/engine-money)

Shipped: usage to invoice. `usage.billPeriod` and `usage.setPrice` (SQL
`bill_usage_period` and `set_usage_price` in the `usage` module) rate
`usage_history` by a per-meter price table into a draft invoice, once per tenant and period.

Not shipped, each needing its own change because it touches several blocks, a public API and
migrations that must be reviewed together:

- Native subscription rows in `billing` with `prorate_change()` posting to `ledger`. The `billing`
  block adopts the app's Stripe-synced `subscriptions` table today, so native rows need an
  ownership decision first.
- `saas.billPeriod`. The `saas` composite has no `usage` or `invoices` part, so the helper stays
  on the `usage` client until the composite lists them.
- Notification digest (`notification_preferences`, `digest_run`) through the `mailer` port.
- The consent gate (`requires_consent`) and `consents.purposes` contributions.
- Revenue recognition schedules and `post_recognition(period_end)`, which wait for the period
  engine.
- The `commissions` and `referrals` blocks.
