# 0427: Scale baseline and the measure-first verdicts

- Status: accepted
- Date: 2026-11-08
- Amends: 0471

## Context

The scale work needs numbers from a database that is large enough to show a
problem. CentraKit develop is readable through the Supabase MCP (read-only), and
the local stack can hold a generated fixture. Eight functions in the scale report
were marked "measure first".

## Decision

`supabase/tests/scale` (D7) holds fixtures that print `SCALE_MS` and
`SCALE_CALLS` diag lines and assert trigger counts:

- `scale_attachments_read`: customers and attachments in one tenant, read as a
  member (ADR 0424).
- `scale_count_modes`: exact and capped counts (ADR 0425).
- `scale_import_batch`: one `import_upsert_batch` call of 1,000 customers. It
  took 439 ms with 1,000 `search_refresh` calls and no `audit_row_change`.

`bsb.scale_rows` resizes the first two. A 1,000,000-row seed did not finish in
six minutes on the shared machine (the customer triggers dominate), so the
documented runs used 60,000 and 200,000 rows. `supabase test db` runs only
`supabase/tests/database`, so these run on request:
`supabase test db supabase/tests/scale/<file>`.

Measure-first verdicts, from `pg_stat_statements` on CentraKit develop:

| Item                                | Calls   | Mean     | Total | Verdict                                                                                                                    |
| ----------------------------------- | ------- | -------- | ----- | -------------------------------------------------------------------------------------------------------------------------- |
| `document_freeze` (trigger)         | 47,668  | 4.65 ms  | 221 s | Candidate. Needs the plan of one call; the fix (skip unchanged parents) is a medium import item. No change here.           |
| `sync_number_sequences`             | 42 (+1) | 4,473 ms | 188 s | Candidate: the largest per-call cost. Not changed without its plan.                                                        |
| `purge_job_archive`                 | 231     | 565 ms   | 130 s | Candidate, run by a scheduled job so latency is not user-facing. No change.                                                |
| `unreported_usage`                  | 114     | 829 ms   | 95 s  | Candidate, also scheduled. No change.                                                                                      |
| `attachments_changed` per statement | none    | none     | none  | Not measurable: the table holds one row on develop. No change.                                                             |
| `session_active()` memo             | none    | none     | none  | No call stats (`track_functions` is off); the plan's 0.7 ms warm and 4.6 ms cold stand. No change until calls are counted. |
| `audit_events` monthly partitions   | none    | none     | none  | The table is not in the develop database's statistics, so there is nothing to partition. No change.                        |

## Consequences

Nothing in the library changes for the verdicts. The next step for the four
candidates is `EXPLAIN (ANALYZE, BUFFERS)` of one call inside `begin ... rollback`
on develop, which this change did not run.
