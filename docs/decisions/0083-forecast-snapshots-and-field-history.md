# 0083: Snapshot the forecast with its deals, and record field changes with a trigger per tracked table

- Status: accepted
- Date: 2026-10-22

## Context

A weekly forecast review compares this week's call with last week's: which
deals moved, which were won, which slipped out of the quarter.
`deals.forecast` computes the call live, so last week's numbers are gone.
Sales teams also ask who changed a deal's amount or close date, and when.
The state-machine history covers stage moves only, and the audit block
records events, not column values.

## Decision

Add a `forecasts` block (`src/sql/modules/forecasts.ts`,
`src/blocks/forecasts/`). `take_forecast_snapshot` stores the
`deal_forecast` totals for a period, currency and optional pipeline in
`forecast_snapshots`, and copies each deal behind them (open deals closing
in the period, deals won or lost in it) into `forecast_snapshot_deals`. It
runs as security definer and sums every deal of the organization, so a
snapshot reads the same for every member who opens it. `forecast_changes`
compares two snapshots of the same organization and currency deal by deal.
Each snapshot writes `forecast.snapshotted`. The block adds
`forecasts.read` and `forecasts.snapshot`; `DealForecast` and its decoder
move to `src/blocks/deal-forecast.ts` so both blocks share them.

Add a `field-history` module (`src/sql/modules/field-history.ts`,
`src/blocks/field-history/`). Its `subjects` option names database columns
per registered subject type; the module renders an
`after update of <columns>` trigger on each table that writes one
`field_changes` row per changed column, with the old and new value as
`jsonb`, `auth.uid()` and the time. Reading needs `history.read` and read
access to the record through `can_subject`.

## Alternatives considered

- Storing only the totals of a snapshot. The review then can't say which
  deals moved, and recomputing from today's deals gives today's answer.
- One generic trigger with `to_jsonb(old)` and `to_jsonb(new)` on every
  column. It records noise (`updated_at`, ranks, search vectors) and wide
  rows on every write; naming the columns keeps the table small.
- Building field history on the audit log. Audit records actions with
  hash-chained rows for compliance (ADR 0034); per-column values at write
  rate would grow that chain for a UI feature.

## Consequences

A review page renders from two snapshot ids without touching live deals,
and a cron can snapshot weekly through the service role. A snapshot copies
deals, so its size grows with the pipeline; the data-lifecycle module can
expire old snapshots. Field history tracks only the configured columns, and
a newly tracked column has no history from before its trigger existed.
Values are JSON, so a bigint amount reads as a number, exact up to 2^53.
There is no UI recipe yet, and both blocks are only in the `everything`
preset.
