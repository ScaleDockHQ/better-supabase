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

## Deferred: Postgres features (phase 8)

Shipped, all opt-in with a default of off so existing databases render the same
SQL: the `@bsb search` tag and the `searchColumn` option (contacts, deals,
tasks, invoices, drive texts), the `noOverlap` exclusion constraints (leases,
calendar events, passes), `partitioned` for `field_changes`, and the BS360
doctor check. They follow ADR 0198.

Deferred, with the reason:

- Feeding `search_documents` from the `search_tsv` column: the search block
  indexes through its own trigger and ranking, so merging the two needs a
  design of its own.
- Partitioning `pipeline_stage_history` and the timeline activity table: both
  rely on a unique constraint without the time column (the one open row per
  record, and the unique event with `on conflict`), which a partitioned table
  can't keep.
- SLA event partitioning and maintenance window exclusions: neither has a
  table to attach to yet.
- `outbox.backend: "pgmq"` with a native DLQ, and statement-level triggers with
  transition tables for the outbox and metrics rollups: both change the
  delivery contract of the outbox and need their own change with an
  integration test against the stack.
