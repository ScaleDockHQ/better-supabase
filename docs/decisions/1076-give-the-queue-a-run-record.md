# 1076: Give the queue a run record

- Status: accepted
- Date: 2026-11-15
- Amends: 0857, 1034

## Context

Twenty blocks enqueue work and only the workflow, import, export, bulk and
webhook calls could be read back with `jobs.get` (EX-1324). A queued message
had no record a client could read: `stats` counts messages and `listDead` lists
only the dead ones.

## Decision

The queue module (version 15) adds `get_job(queue, job_id)`, which returns one
message as `jsonb` without its payload: `state` (`waiting`, `running`, `done`
or `dead`), `attempts`, `maxAttempts`, `enqueuedAt`, `finishedAt`, `lastError`.
It exists for the pgmq and the table backend, is service-only like the other
queue functions, and returns `null` for an unknown or purged message. The
client adds `get`, `enqueueJob` (returns `{ jobId: "queue:<queue>:<id>" }`) and
`runs`, the `queue` source of `createJobs`. `waiting` is `pending`, `running`
is `running`, `done` is `completed` and `dead` is `failed` with the hint
`QUEUE_JOB_DEAD`. The Vercel backend returns `invalid_request` for `get`, as it
does for `stats`.

One generic record serves every block that enqueues, instead of one SQL
function per block. A block that returns the message id of its own enqueue can
return the same ref. A block whose queue message has no per-message meaning for
the caller (a call that fans out many messages and returns a count) records
that reason in its audit row instead.

## Consequences

Apps run `better-supabase upgrade` and apply the migration. The payload stays
out of the record, so reading it needs no extra permission check beyond the
service role.
