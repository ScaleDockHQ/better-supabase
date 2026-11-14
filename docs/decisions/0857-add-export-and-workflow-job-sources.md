# 0857: Add the export and workflow job sources

- Status: accepted
- Date: 2026-11-14

## Context

ADR 0852 gave long calls one `{ jobId }` and a common `jobs.get`, with
`bulk-actions` and `imports` as the first sources. EX-1324 still named the other
blocks that use the jobs queue. Most of them have no run the caller can read
back: a webhook delivery or a reminder is a message, not a record with a
status. Two blocks do keep a readable record per long call.

## Decision

`data-lifecycle` is the `export` source: `startExportJob(options)` returns
`{ jobId: "export:<id>" }` and `jobs.get` reads the export through
`get_data_export`, so the caller sees the exports their policies show.
`pending` and `running` pass through, `ready` is `completed` with the export as
`result`, and `failed` has the hint `DATA_EXPORT_FAILED`. `workflows` is the
`workflow` source: `jobs.get` reads a run through `runs.get`, `queued` is
`pending`, `waiting` is `running`, and `failed` and `cancelled` are `failed`
with `WORKFLOW_RUN_FAILED` or `WORKFLOW_RUN_CANCELLED`. Engines still start
workflow runs, so `workflows` has no start call.

## Alternatives considered

- Make every queue block a source: a message with no record has no status to
  read, so the source would invent one.
- Read tenant exports through the source: `get_data_export` already returns
  them when the caller may see them, so no option is needed.

## Consequences

`createJobs({ bulk, import, export, workflow })` covers four kinds. Blocks
that only enqueue work, such as webhooks and reminders, are not sources and the
audit row says so.
