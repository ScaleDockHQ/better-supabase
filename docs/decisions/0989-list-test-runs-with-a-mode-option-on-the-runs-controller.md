# 0989: List test runs with a mode option on the runs controller

- Status: accepted
- Date: 2026-11-14

## Context

`runs.list` already takes `mode` (`live`, `test` or `all`) and defaults to
`live`. `createWorkflowRunsController` and `useWorkflowRuns` did not pass it
through, so the example editor kept the ids of the test runs it started and
merged them into the run picker. A test run started in another tab, or before
a reload, did not appear (finding EX-205).

## Decision

`createWorkflowRunsController` and `useWorkflowRuns` take `mode` and pass it to
`runs.list`. The default stays `live`, so existing callers see no change.
`WorkflowRunMode` is exported from `better-supabase/blocks/workflows`. The
example editor lists with `mode: "all"`, labels test runs from `run.mode` and
no longer tracks ids in state. The run detail labels the version of a test run
as a hidden test snapshot (EX-213), and `globals.css` maps React Flow's palette
variables to the app tokens so the minimap and controls follow dark mode
(EX-212).

## Alternatives considered

A separate `useWorkflowTestRuns` hook: a second controller for the same list
call. Making `all` the default: it would add test runs to every existing live
list.

## Consequences

The picker stays in sync with the database. Test runs started by other
sessions show for everyone who can read the definition's runs.
