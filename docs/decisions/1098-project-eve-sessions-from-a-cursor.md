# 1098: Project eve sessions from a cursor, not from hooks

- Status: accepted
- Date: 2026-11-20

## Context

`persistSessions` wrote the chat tables from nine eve hooks. eve does not retry
a hook, so a failed write lost an event for good. The handlers also skipped a
session without a signed-in user and tenant, recorded no steps, usage or
approvals, and never set `ai_runs.external_run_id`.

## Decision

The `workflow-sdk` module (version 7, ADR 0699 keeps one key per block) adds
`workflow.eve_sessions` and `workflow.eve_session_runs`. A trigger on
`workflow_runs` and one on `workflow_events` mark a session dirty and queue a
job in `eve_session_sync` through `enqueue_job`, whose `dedupe_key` absorbs a
burst into one waiting job. The `eve_session_*` functions lease a session,
commit a cursor and list sessions that are behind.

`createSessionSync` runs in the eve server and reads the session stream
through eve's public reader (`sessions.attach(...).stream({ startIndex,
follow: false })`) from the stored cursor, because decoding
`workflow_stream_chunks` would tie the code to Workflow's framing and
encryption. A pass writes every fact with a key derived from the event, then
commits the cursor, so a failed pass runs again without duplicates. A pass whose
turn already has an ended run opens no second run.

`persistSessions` becomes wake-only: it takes `store` instead of `chats` and
calls `eve_session_wake`. This is a breaking change to the options.
`purgeRuns({ skipUnprojected })` keeps runs of open or unsynced sessions.
`cancel_approval` takes an optional reason, appended to the audit summary.

## Consequences

- The sync job needs the eve server process, so a deployment schedules
  `sweepSessions` there.
- ADR 1097 covers the World DDL for world-postgres 5.4.0 (migrations 0031 and 0032) and the module version 6.
- Sessions without a resolved tenant are skipped and their cursor moves.
