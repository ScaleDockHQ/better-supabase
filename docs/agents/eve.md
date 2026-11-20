# eve on the Supabase World

Gap report for running eve 1.2.0 on the Supabase World and projecting its
sessions into the blocks. Read it before you change `src/eve`,
`src/workflow-sdk/world` or the `workflow-sdk` SQL module.

Status values: `done`, `partly`, `missing` and `unproven`. Unproven means only
a live run on Vercel can settle it; `scripts/eve-vercel-check.ts` collects the
numbers and the report records them once a maintainer runs it.

## Version line

| Package                      | Floor                                                              | Passes `minimumReleaseAge` |
| ---------------------------- | ------------------------------------------------------------------ | -------------------------- |
| `eve`                        | 1.2.0 (bundles `@workflow/core` 5.7.0 and `@workflow/world` 5.3.0) | 2026-11-21 15:55 UTC       |
| `workflow`, `@workflow/core` | 5.7.0                                                              | 2026-11-20 20:41 UTC       |
| `@workflow/world`            | 5.3.0                                                              | 2026-11-20 20:41 UTC       |
| `@workflow/world-postgres`   | 5.4.0                                                              | 2026-11-20 20:41 UTC       |

eve 1.1.0 bundles core 5.6.1 and world 5.2.2, so it is not the supported line.
Never lower or bypass `minimumReleaseAge`; read versions with `pnpm view` when
you bump.

## Facts the code relies on

- eve does not retry or rerun hooks. A hook runs once per event.
- eve stamps `$eve.version` on every run and `$eve.session` on handoff
  successors. No other run attribute names a tenant or a principal.
- `WORKFLOW_ENCRYPTION_KEY` is read by none of the SDK packages. Keys come only
  from `World.getEncryptionKeyForRun`.
- Core's default stream flush interval is 0, not 10.
- On Vercel, eve's flow route has a Vercel Queues trigger and `pg_net` cannot
  reach it, so it needs the `vercel-queue` delivery mode.
- Migration 0031 adds `workflow.workflow_run_delivery_leases`. Migration 0032
  adds `workflow_runs.wake_pending`; upstream backfills existing rows with
  `true`, then sets the default to `false`.
- No structural type in `src/eve` breaks from eve 1.0.0-rc.13 to 1.2.0
  (stream version 27, approvals and the session reader are unchanged).

## Part A: the World

| Item                              | Status                                                                                                                                                                                                                                                            | Where                                                    | Test                                                                         |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- | ---------------------------------------------------------------------------- |
| A1 Pins and migrations 0031, 0032 | done (ADR 1097): pins are 5.3.0 and 5.4.0, the module is version 6 with a `wake_pending` backfill, and a stub manifest carries the range                                                                                                                          | `src/workflow-sdk/world/types.ts`, `pnpm-workspace.yaml` | `tests/workflow-sdk/world/manifest.test.ts`                                  |
| A2 eve loads the World            | partly: default export and `createWorld()` exist; eve skips its major-version check for a subpath specifier; the Vercel build is unproven (the World is bundled with `pg` unless `better-supabase` is in `build.externalDependencies`)                            | `src/workflow-sdk/world/index.ts`                        | `tests/workflow-sdk/world` ("shares one World per connection and namespace") |
| A3 eve's required capabilities    | done for storage: atomic start hook and the spec 9 fence pass `@workflow/world`'s conformance suites in poll and pg_net mode; retention 0 and stream resume are asserted; handoff, steering and parked hooks across a restart need eve's runtime and are unproven | `src/workflow-sdk/world/world.ts`                        | `tests/integration/workflow-world-conformance`, `workflow-world-eve`         |
| A4 Delivery                       | partly: signing, 73 deliveries, dead letters, extra headers, `vercel-queue` mode and the owed wake-up sweep are tested (the Vercel side with a fake client only); a `pg_net` enqueue dispatches at once                                                           | `src/workflow-sdk/world/`                                | `tests/workflow-sdk/world`                                                   |
| A5 Pooling and streams            | done: `connection` modes (transaction mode polls streams, omits the `LISTEN` listeners), pool 2 on serverless, flush default 20 ms; no benchmark                                                                                                                  | `world.ts`, `polling.ts`                                 | `tests/workflow-sdk/world/polling.test.ts`, `workflow-world-eve`             |
| A6 Encryption                     | done: key ring with time-based selection, missing-key warning; no key id stored per run; the canary scan of every table is unproven                                                                                                                               | `crypto.ts`, `world.ts`                                  | `tests/workflow-sdk/world/crypto.test.ts`                                    |
| A7 Run attribution                | partly: tenant and principal live in `eve_sessions`; done: the sync sets `ai_runs.external_run_id` to the session's newest run id                                                                                                                                 | `src/eve/sessions.ts`                                    | none                                                                         |
| A8 Session upgrades               | missing, apart from `cancelRuns`                                                                                                                                                                                                                                  | `maintenance.ts`                                         | none                                                                         |
| A9 Retention                      | partly: `purgeRuns` is tested; `purgeRuns({ skipUnprojected })` keeps runs the sync has not read; retention is undocumented for eve                                                                                                                               | `maintenance.ts`                                         | `tests/workflow-sdk/world`                                                   |
| A10 `eve dev` with a custom World | unproven: eve's code honours a configured World; nothing here documents or tests it                                                                                                                                                                               | none                                                     | none                                                                         |

## Part B: persistence

| Item                | Status                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | Where                 |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------- |
| B1 to B5 Projection | done (ADR 1098): `eve_sessions` and `eve_session_runs` in the `workflow-sdk` module (version 7), triggers that queue a debounced `eve_session_sync` job, `createSessionSync` (cursor, lease, keyed writes, steps, approvals, inputs, usage), wake-only `persistSessions`, `sweepSessions`, `sessionHistory`, `openSessions` and `endStrandedSessions`. Tests: `tests/eve/{sync,sessions,store,upgrade,history}.test.ts` and the live eve and workflow-sdk integration tests | `src/eve/sessions.ts` |

Design decision: `syncSession` reads through eve's public reader
(`sessions.attach` from `eve/server`) with `stream({ startIndex: cursor,
follow: false })`. Decoding `workflow_stream_chunks` directly would couple the
code to Workflow's framing and encryption and to eve's line format, and it
breaks on Vercel Workflow. The cost is that the sync job runs inside the eve
server process.

## Part C: blocks and SDKs

| Item            | Status                                                                                                                                                                                                        | Notes                                              |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| C1 Types        | done: no structural type breaks; dynamic schedule `scopes` and `validateExpression` are unsupported                                                                                                           | `src/eve/types.ts`                                 |
| C2 Chat sharing | done: organization visibility, participants, a revocable live link (integration test) and a `modes` option with a check constraint                                                                            | `ai-chat`                                          |
| C3 Inbox on eve | done (ADR 1099): `inboxConnectionWebhook`, `inboxHandoff`, `inboxRunAs` and `inboxReplies` (send or draft); `routeInbox` stays for Chat SDK apps; unproven against a live eve channel                         | `src/eve/inbox.ts`                                 |
| C4 TTL          | done: every `ttl_ms` is `bigint`; tests "sends a 30-day TTL as a plain number" and "stores thread state under a 30 day TTL"                                                                                   | chat-sdk state                                     |
| C5 Memory       | done: `supabaseMemory({ scopes })` and `importMemories`; named scopes are type-checked against eve 1.2.0 (`tests/eve/memory-scopes-types.test.ts`)                                                            | `src/eve` memory                                   |
| C6 Knowledge    | done: `pdfExtractor` and `docxExtractor` load the optional peers `unpdf` and `mammoth` (or take `load`), `createUrlSource` with `resync`, chunk `position`                                                    | knowledge block                                    |
| C7 Schedules    | done: `validateExpression`, scopes, failure notices, `aiScheduleDispatch` and `queueScheduleProvider({ mirror })`, which writes `ai_scheduled_tasks` and `ai_task_runs` under a `source` the dispatcher skips | `src/eve/schedules.ts`, `dynamic-schedules.ts`     |
| C8 Approvals    | done: `strictestApproval(...policies)` combines policies and `permission` derives `scopes` (changeset `eve-strictest-approval`)                                                                               | `src/eve/tools.ts`                                 |
| C9 Guide        | missing                                                                                                                                                                                                       | `apps/docs/content/docs/(docs)/(integrations)/eve` |

## Verification on Vercel

No Vercel deployment is available to the agents that work on this repository.
A maintainer runs `node scripts/eve-vercel-check.ts <deployment-url>` and
pastes the output here. Until then these stay unproven: the Vercel build with
and without `build.externalDependencies`, the private flow route, time to
first token, reconnect time and the comparison with Vercel Workflow. Enable
Vercel Queues on the project that hosts the eve service before the run.

## Order of work

1. Phases that need only the current versions: block modes and live-link
   tests, chat state upgrade tests, memory scopes and import, knowledge
   extractors, schedules, `strictestApproval`, and the projection written
   against structural types.
2. After the release-age gates: the catalog bump, trust exclusions (each with
   its trust date, recorded in an ADR), the World DDL regeneration against the
   local stack (migrations 0031 and 0032), and the next workflow-sdk module
   version (7: version 6 holds the eve session projection).
