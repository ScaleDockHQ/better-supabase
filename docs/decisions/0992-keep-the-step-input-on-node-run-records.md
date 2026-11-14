# 0992: Keep the step input on node run records

- Status: accepted
- Date: 2026-11-14

## Context

Node run records kept a node's status, output and error but not what it
received, so the run detail showed the node's config next to its output
(finding EX-202).

## Decision

`workflow_node_runs` gains a nullable `input` column.
`record_workflow_node_run` takes `input` as a last argument with a default of
null and keeps an earlier input when a later record has none, so the
`running` record carries it and the `completed` record does not repeat it.
`nodeRunReporter` records `call.input` with `running`, `NodeRunRecord` and
`WorkflowNodeRun` gain `input`, and the run detail shows an Input block above
the Output block.

## Alternatives considered

Storing the input on the `completed` record: a failed or waiting node would
show no input. A separate table: one row per node already exists.

## Consequences

The migration drops the six-argument function, so a caller that omits `input`
still resolves to the new one through the default. An app that owns its
node-run table gets the column from the module's `add column if not exists`.
The input can be large; it is stored as given, as the output is.
