# eve on the Supabase World

Gap report for running eve 1.4.0 on the Supabase World and projecting its
sessions into the blocks. Read it before you change `src/eve`,
`src/workflow-sdk/world` or the `workflow-sdk` SQL module.

Status values: `done`, `partly`, `missing` and `unproven`. Unproven means only
a live run on Vercel can settle it; `scripts/eve-vercel-check.ts` collects the
numbers and the report records them once a maintainer runs it.

## Version line

| Package                      | Floor                                                              | Passes `minimumReleaseAge` |
| ---------------------------- | ------------------------------------------------------------------ | -------------------------- |
| `eve`                        | 1.4.0 (bundles `@workflow/core` 5.7.0 and `@workflow/world` 5.3.0) | passed 2026-11-24          |
| `workflow`, `@workflow/core` | 5.8.0                                                              | 2026-11-25 00:17 UTC       |
| `@workflow/world`            | 5.4.0                                                              | 2026-11-25 00:16 UTC       |
| `@workflow/world-postgres`   | 5.5.0                                                              | 2026-11-25 00:17 UTC       |

eve 1.1.0 bundles core 5.6.1 and world 5.2.2, so it is not the supported line.
eve checks only the major of the `@workflow/world` range, so eve 1.4.0 loads the
World that speaks world 5.4; eve 1.5.0 bundles Workflow 5.8 and passes
`minimumReleaseAge` on 2026-11-26.
All of these releases now pass `minimumReleaseAge`, and
`pnpm-workspace.yaml` has no `minimumReleaseAgeExclude` entries.
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
- No structural type in `src/eve` breaks from eve 1.0.0-rc.13 to 1.4.0
  (stream version 27, approvals and the session reader are unchanged).
- world-postgres 5.5.0 ends a zero-retention run by calling
  `<GRAPHILE_WORKER_SCHEMA>.add_job` inside the terminal transaction. The World
  sets the schema to `workflow`, where module version 9 and later record the call as a
  purge backstop instead of running Graphile Worker.
- world-postgres 5.5.0 adds `workflow.workflow_rate_limits` (migration 0033) and
  turns on `rateLimits`, which needs `inBandFence`. The World mints spec 8 runs
  (ADR 1106), so it turns `rateLimits` off and module version 10 only creates
  the empty table (ADR 1248).

## Part A: the World

| Item                              | Status                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | Where                                                    | Test                                                                         |
| --------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- | ---------------------------------------------------------------------------- |
| A1 Pins and migrations 0031, 0032 | done (ADR 1097): pins are 5.4.0 and 5.5.0 (ADR 1248), the module is at version 10 (6 adds the tables and the `wake_pending` backfill, 7 the projection, 8 the dispatcher headers and `vercel-queue`, ADR 1100; 9 the purge backstops; 10 `workflow_rate_limits`), and a stub manifest carries the range                                                                                                                                                                                                                                                                                                                                | `src/workflow-sdk/world/types.ts`, `pnpm-workspace.yaml` | `tests/workflow-sdk/world/manifest.test.ts`                                  |
| A2 eve loads the World            | partly: default export and `createWorld()` exist; eve skips its major-version check for a subpath specifier; the Vercel build is unproven (the World is bundled with `pg` unless `better-supabase` is in `build.externalDependencies`)                                                                                                                                                                                                                                                                                                                                                                                                 | `src/workflow-sdk/world/index.ts`                        | `tests/workflow-sdk/world` ("shares one World per connection and namespace") |
| A3 eve's required capabilities    | done on the local stack: `tests/eve-world` runs eve 1.4.0 on the World and passes start, tool call (every step at attempt 1), approval park and resume, compaction with handoff (hook retained), session end, queued input, steering, stream resume from an index, a parked hook across a restart, idle timeout, retention 0 and default, in `eve dev` and `eve start`, poll and transaction connection, and `pg_net` delivery (39 tests, about 160 s); `vercel-queue` delivery cannot run locally and is unproven under eve                                                                                                           | `src/workflow-sdk/world/world.ts`                        | `tests/integration/workflow-world-conformance`, `workflow-world-eve`         |
| A4 Delivery                       | done for poll and `pg_net` under eve; `vercel-queue` mode is tested with a fake client only; no Vercel build was run                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | `src/workflow-sdk/world/`                                | `tests/workflow-sdk/world`                                                   |
| A5 Pooling and streams            | done: measured with `pnpm bench:eve-world` (200 tokens a turn, one token per 10 ms, median of 3): rows per 1,000 tokens 1,055 at every flush; statements per 1,000 tokens 3,311 at 0 ms, 2,582 at 20 ms, 1,717 at 50 ms, 1,617 at 100 ms; time to first event 20, 41, 71, 160 ms; reconnect from an index 2 ms. The default stays 20 ms, which keeps first-token latency near 40 ms; 50 ms saves a third of the statements for 30 ms more. Transaction mode still holds one idle `LISTEN` per process (session mode two) because `@workflow/world-postgres` opens it when the streamer is created; closing it needs an upstream change | `world.ts`, `polling.ts`                                 | `tests/workflow-sdk/world/polling.test.ts`, `workflow-world-eve`             |
| A6 Encryption                     | done: key ring with time-based selection, the key id stamped per run as `$bsb.key_id` (ring of two or more keys), documented rotation, the missing-key warning (seen under `eve start`), and a canary scan of every `workflow` table that finds nothing with a key and finds the canary without one; run attributes such as `$eve.title` are plain text                                                                                                                                                                                                                                                                                | `crypto.ts`, `world.ts`                                  | `tests/workflow-sdk/world/crypto.test.ts`                                    |
| A7 Run attribution                | partly: tenant and principal live in `eve_sessions` (`tests/eve/store.test.ts`); the sync sets `ai_runs.external_run_id` to the session's newest run id, which no unit test asserts                                                                                                                                                                                                                                                                                                                                                                                                                                                    | `src/eve/sessions.ts`                                    | `tests/eve/store.test.ts`                                                    |
| A8 Session upgrades               | done: `openSessions` lists the open sessions on another eve version and `endStrandedSessions` marks them `stranded` and cancels their runs with `cancelRuns` (dry run supported); not run against a real eve upgrade                                                                                                                                                                                                                                                                                                                                                                                                                   | `src/eve/upgrade.ts`, `src/workflow-sdk/runs.ts`         | `tests/eve/upgrade.test.ts`                                                  |
| A9 Retention                      | done: `purgeRuns` is tested; run retention `0` clears run data on completion (integration test) and a handoff still retains the hook until it expires; `purgeRuns({ skipUnprojected })` keeps runs the sync has not read; `purgeBackstops` and `workflow_purge_backstops()` finish the purge of a zero-retention run whose terminal purge failed (the World sweeps in poll mode, pg_cron every minute in the other modes)                                                                                                                                                                                                              | `maintenance.ts`                                         | `tests/workflow-sdk/world`                                                   |
| A10 `eve dev` with a custom World | done: `eve dev` with `experimental.workflow.world` set boots on the World, writes no `.eve/.workflow-data` and stores its runs in Postgres (`tests/eve-world/tests/lifecycle.test.ts`)                                                                                                                                                                                                                                                                                                                                                                                                                                                 | none                                                     | none                                                                         |

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

| Item              | Status                                                                                                                                                                                                           | Notes                                              |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| C1 Types          | done: no structural type breaks; dynamic schedule `scopes` and `validateExpression` are supported by the provider, and eve's own `scopes` option is not exercised by a live eve run                              | `src/eve/types.ts`                                 |
| C2 Chat sharing   | done: organization visibility, participants, a revocable live link (integration test) and a `modes` option with a check constraint                                                                               | `ai-chat`                                          |
| C3 Inbox on eve   | done (ADR 1099): `inboxConnectionWebhook`, `inboxHandoff`, `inboxRunAs` and `inboxReplies` (send or draft); `routeInbox` stays for Chat SDK apps; unproven against a live eve channel                            | `src/eve/inbox.ts`                                 |
| C4 TTL            | done: every `ttl_ms` is `bigint`; tests "sends a 30-day TTL as a plain number" and "stores thread state under a 30 day TTL"                                                                                      | chat-sdk state                                     |
| C5 Memory         | done: `supabaseMemory({ scopes })` and `importMemories`; named scopes are type-checked against eve 1.4.0 (`tests/eve/memory-scopes-types.test.ts`)                                                               | `src/eve` memory                                   |
| C6 Knowledge      | done: `pdfExtractor` and `docxExtractor` load the optional peers `unpdf` and `mammoth` (or take `load`), `createUrlSource` with `resync`, chunk `position`                                                       | knowledge block                                    |
| C7 Schedules      | done: `validateExpression`, scopes, failure notices, `aiScheduleDispatch` and `queueScheduleProvider({ mirror })`, which writes `ai_scheduled_tasks` and `ai_task_runs` under a `source` the dispatcher skips    | `src/eve/schedules.ts`, `dynamic-schedules.ts`     |
| C8 Approvals      | done: `strictestApproval(...policies)` combines policies and `permission` derives `scopes` (changeset `eve-strictest-approval`)                                                                                  | `src/eve/tools.ts`                                 |
| C9 Guide          | done: the guide is split into ten pages (World and delivery modes, sign-in, tools, approvals, schedules, connections, memory, sessions, inbox) and the migration guide `0.79-to-0.80` lists the breaking changes | `apps/docs/content/docs/(docs)/(integrations)/eve` |
| C10 Custom skills | done: `supabaseSkillScopes` keys eve's experimental custom skills by tenant (personal, persona, channel, organization) and stores them through `supabaseDocumentBackend`; not run in a live eve session          | `src/eve/skills.ts`, `tests/eve/skills.test.ts`    |

## Verification on Vercel

No Vercel deployment is available to the agents that work on this repository.
A maintainer runs `node scripts/eve-vercel-check.ts <deployment-url>` and
pastes the output here. Until then these stay unproven: the Vercel build with
and without `build.externalDependencies`, the private flow route, time to
first token, reconnect time and the comparison with Vercel Workflow. Enable
Vercel Queues on the project that hosts the eve service before the run.

## Manual steps for the maintainer

1. Enable Vercel Queues on the Vercel project that hosts the eve service, set
   `WORKFLOW_DELIVERY=vercel-queue`, deploy, then run
   `node scripts/eve-vercel-check.ts <deployment-url>` and paste the output
   under "Verification on Vercel". Run it with and without
   `build.externalDependencies: ["better-supabase"]` to settle A2.
2. Connect a live inbox channel (a connection with a real credential) and send a
   message in bot mode to settle C3.
3. Run the live checks no agent can: the AI Gateway, Vercel Sandbox mounts,
   Vercel Connect (`teamId`, `orgId`) and the Resend channel config.
4. After 2026-12-09 17:48 UTC, 2026-12-12 and 2026-12-19 (see
   `pnpm-workspace.yaml`), remove the `trustPolicyExclude` entries once
   `pnpm install` accepts the releases on their own (ADR 1097).

## What stays unproven

- `vercel-queue` delivery under real Vercel Queues (a fake client covers the
  World's side).
- The Vercel build, time to first token and reconnect time on Vercel.
- The live inbox channel and the live gateway, sandbox, connect and resend
  paths.
- Dynamic schedule `scopes` under eve's own resolution.
- Closing the idle `LISTEN` client in transaction mode (blocked upstream).
