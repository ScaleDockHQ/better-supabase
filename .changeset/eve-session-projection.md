---
"better-supabase": minor
---

eve sessions are copied into the chat tables from a cursor instead of from hooks. The `workflow-sdk` module (version 7) tracks sessions in `workflow.eve_sessions` and queues a debounced `eve_session_sync` job, and `createSessionSync` reads each session through eve's reader, then writes the chat, messages, run steps, approvals, pending inputs and usage per model call (`costUsd` in micro-USD), keyed by the event, so a failed pass runs again without duplicates. `syncSession`, `sweepSessions`, `sessionHistory`, `openSessions`, `endStrandedSessions` and `createEveSessionStore` are new, `world.eveSessions` is the store, `ai_runs.external_run_id` holds the eve run id, `purgeRuns({ skipUnprojected: true })` keeps runs the sync has not read, and `approvals.cancel(id, { reason })` records why an approval was cancelled.

Behaviour changes to check:

- `persistSessions` is wake-only and takes `{ store, delaySeconds? }` instead of `{ chats, agentId, title }`. Pass `store: createSupabaseWorld().eveSessions`, run `createSessionSync(...)` where eve's `sessions.attach` is available, and move `agentId` and `title` into its `resolve` option.
- `cancel_approval(request_id, reason)` replaces `cancel_approval(request_id)`. Run `better-supabase upgrade` for the new migration.
- `workflow_purge_runs` takes a fourth argument, `skip_unprojected`.
