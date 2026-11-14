# 0852: Return a job id from long calls

- Status: accepted
- Date: 2026-11-14

## Context

EX-1324 found 20 blocks on the jobs queue and no common way to ask how a long
call is going: each block had its own run table and status shape.

## Decision

`src/core/jobs.ts` defines `{ jobId }` (`<kind>:<id>`), the `JobResult` that
`jobs.get(jobId)` returns (`status`, `progress`, `result`, `error`, `done`) and
`createJobs(sources)`, which reads the kind off the id and asks that source.
An unknown kind is `invalid_input` with `JOB_KIND_UNKNOWN`, an unknown id
`not_found`. `bulk-actions` is the `bulk` source (`startJob` returns the
`{ jobId }`, `jobs.get` maps a run and its per-row results) and `imports` is the
`import` source (a canceled run reads as `failed` with `IMPORT_RUN_FAILED`). A
source reads through the caller's own functions, so `jobs.get` shows only runs
the caller may see.

## Alternatives considered

- One global jobs table: blocks keep their own tables and permissions.
- Expose the pgmq message id: it says nothing about progress.

## Consequences

Other long calls join by exposing a `JobSource`. The queue block itself is not
a source, because a queue message has no result.
