# 1100: Version the workflow-sdk module once per World change, versions 6 to 8

- Status: accepted
- Date: 2026-11-20

## Context

The `workflow-sdk` SQL module holds the World tables, the delivery dispatcher
and the eve projection (ADR 1098). Three changes of the eve line touched it in
one branch: the `@workflow/world-postgres` 5.4.0 tables (ADR 1097), the
projection tables, and the delivery changes for Vercel Queues (ADR 1101).
Apps run `better-supabase upgrade` per module version, and an upgrade step
runs on a database that already holds runs, so each step has to be safe on
that data and has to run in order.

## Decision

Each change gets its own module version and its own upgrade step. An app on
version 5 runs three steps in order and a fresh install runs none. The `from`
column is the version the step upgrades.

| Version | Change                                                                                                                                 | Step                                                                                                                                       |
| ------- | -------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| 6       | `workflow_run_delivery_leases` and `workflow_runs.wake_pending` (migrations 0031 and 0032)                                             | adds `wake_pending` with default `true`, then sets the default to `false`, so existing runs start with an owed wake-up                     |
| 7       | `eve_sessions`, `eve_session_runs`, their triggers and the `eve_session_*` functions; `workflow_purge_runs` takes `skip_unprojected`   | the module file creates them; the step is empty because the objects are new and the file's `create or replace` statements apply (ADR 1098) |
| 8       | `dispatch_workflow_deliveries()` adds the headers in the Vault secret `workflow_delivery_headers`; `delivery` accepts `"vercel-queue"` | the function is replaced by the module file; the step adds no table                                                                        |

The module file adds `wake_pending` with its final default, which would clear
existing rows, so the version 6 step runs the column statements itself.
`tests/sql/workflow-sdk-upgrade.test.ts` asserts that backfill and the step
order. The run key id (ADR 1104) needs no version, because it is a run
attribute.

## Alternatives considered

- One jump to version 8 with a single step. A failed step would leave an app
  between three changes with no record of which one applied.
- Keep the projection in its own module. It reads `workflow_runs` and
  `workflow_events` in triggers and joins `workflow_runs`, so a second module
  would need a second dependency order. ADR 0699 keeps one key per block.

## Consequences

- An app upgrades the module before it deploys `workflow` 5.7, or the World
  fails on the missing `wake_pending` column.
- A change to the World DDL after this needs version 9 and a step, never an
  edit of a step that shipped.
