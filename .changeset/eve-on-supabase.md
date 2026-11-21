---
"better-supabase": minor
---

eve on Supabase moves to eve 1.2 and Workflow 5.7, runs on the Supabase World under the transaction pooler and on Vercel Queues, projects sessions into the chat tables from a cursor, and runs the inbox as an eve channel. The migration guide is [From 0.79 to 0.80](https://bettersupabase.com/docs/migration/0.79-to-0.80).

## Breaking changes

- Peer ranges: `eve >=1.2.0 <2`, `workflow >=5.7.0 <6`, `@workflow/world >=5.3.0 <5.4` and `@workflow/world-postgres >=5.4.0 <5.5`. eve 1.0 release candidates and releases before 1.2.0 are not supported, and `assertWorldMigrations` throws on a `@workflow/world-postgres` older than 5.4.0. The World speaks protocol 5.3.0, and `better-supabase/workflow-sdk/world/package.json` is a stub manifest that carries the `@workflow/world` range for eve's startup check.
- The `workflow-sdk` SQL module is at version 8 and the `ai-schedules` module at version 3 (the `inbox` module at version 11). Run `better-supabase upgrade` before you deploy Workflow 5.7. Version 6 adds `workflow_run_delivery_leases` and `workflow_runs.wake_pending`, and runs that exist before the upgrade start with `wake_pending` set. Version 7 adds the eve projection. Version 8 replaces `dispatch_workflow_deliveries()` and adds no table.
- `persistSessions` is wake-only. It takes `{ store, delaySeconds? }` instead of `{ chats, agentId, title }`: pass `store: createSupabaseWorld().eveSessions`, run `createSessionSync(...)` where eve's `sessions.attach` is available, and move `agentId` and `title` into its `resolve` option.
- `cancel_approval(request_id, reason)` replaces `cancel_approval(request_id)`, and `workflow_purge_runs` takes a fourth argument, `skip_unprojected`.
- `better-supabase/ai-sdk/workflow` passes the tool approval policy to `WorkflowAgent` as `toolApproval` instead of wrapping each tool with `needsApproval`. A denied tool call now ends as an `execution-denied` result, which the model sees, instead of an error.
- `createAssistant` stores a stream that failed after it started as an `error` message, releases the run as `failed` with the error text, and calls `onFinish` with `status: "failed"`. Before, the answer was stored as `complete`.
- `GatewayAccessPolicyDeniedError` maps to a `forbidden` error with code `AI_GATEWAY_ACCESS_POLICY_DENIED`.
- The `ai-schedules` dispatcher only claims tasks whose `source` is `ai-schedules`.
- The stream flush interval of the World defaults to 20 ms, and the pool holds 2 connections by default on Vercel, AWS Lambda and Netlify.
- The inbox keeps one `ai` draft per conversation and `replyKey` in any status (inbox module version 11 adds the unique index `inbox_drafts_ai_key`).

## The World

- `delivery: "vercel-queue"` (or `WORKFLOW_DELIVERY=vercel-queue`) delivers over Vercel Queues. `@vercel/queue` is an optional peer loaded on first use. It sends each message to its `__wkf_*` topic, splits delays over 23 hours into hops, and answers Vercel's retry with the World's backoff and the 73 delivery limit. It runs only on Vercel, so a fake client tests it.
- `deliveryHeaders` (`WORKFLOW_DELIVERY_HEADERS` or the Vault secret `workflow_delivery_headers`) adds headers such as `x-vercel-protection-bypass` to poll and `pg_net` deliveries, and `recoverAfter` (`WORKFLOW_RECOVER_AFTER_SECONDS`) sets how long an owed wake-up waits before the World queues it again. The World clears `wake_pending` when an orchestrator delivery completes and sweeps stale flags. `delivery: "poll"` on Vercel logs a warning.
- `connection: "transaction"` (chosen on port 6543, or with `WORKFLOW_POSTGRES_CONNECTION`) polls stream readers and omits the `LISTEN` based feeds, so the World no longer warns on the pooler. The warning appears only for `connection: "session"` on a pooled URL.
- `encryptionKeys` (`WORKFLOW_ENCRYPTION_KEYS`, Vault secret `workflow_encryption_keys`) takes a ring of master keys. With more than one key, the World stamps the key id on each new run as the attribute `$bsb.key_id`, so a run keeps opening with its key when a `from` date changes. `world.start()` warns when no key is set outside development and test.
- New exports from `better-supabase/workflow-sdk/world`: `isServerless`, `parseKeyRing`, `ringKeyFor`, `runCreatedAt`, `RingKey`, `WorldConnection`.

## eve

- `createSessionSync` copies sessions into the chat tables from a cursor, read through eve's reader and keyed by event. `syncSession`, `sweepSessions`, `sessionHistory`, `openSessions`, `endStrandedSessions` and `createEveSessionStore` are new, `world.eveSessions` is the store, `ai_runs.external_run_id` holds the eve run id, `purgeRuns({ skipUnprojected: true })` keeps runs the sync has not read, and `approvals.cancel(id, { reason })` records why an approval was cancelled.
- `inboxConnectionWebhook`, `inboxHandoff`, `inboxRunAs` and `inboxReplies` run the inbox on eve without Chat SDK. `createSessionSync` takes a `reply` handler.
- `strictestApproval(...policies)` combines approval policies, and `supabaseTool`, `eveContext` and `approvalPolicy` accept `permission`, a key or keys that join `scopes` in the agent's `scope` claim.
- `supabaseMemory({ scopes })` recalls and writes the user, organization and record scopes. `validateExpression`, `queueScheduleProvider({ scopes, minIntervalMs, validateExpression, mirror })`, `queueDynamicSchedules({ notify, staleAfterMs })` and `aiScheduleDispatch` manage schedules, and `mirror` writes eve's schedules and occurrences to `ai_scheduled_tasks` and `ai_task_runs`.

## Blocks and adapters

- `ai-chat`: a `modes` option adds a check constraint on `mode` and narrows its type.
- `memory`: `importMemories` copies a table into archival memory, and `archival.upsert` takes `embedding` and `embeddingModel`.
- `knowledge`: `position` (offsets, page, heading) on chunks and hits, `pdfExtractor`, `docxExtractor` and `extractors`, and `createUrlSource` with `resync`, `resyncAll` and fetch guards. `unpdf` and `mammoth` are new optional peers (`>=2.2.1 <3` and `>=1.13.0 <2`).
- `ai-schedules`: tasks have a `source` and an `externalId`, and the service functions `mirror`, `unmirror` and `recordRun` let another scheduler keep tasks and runs.
- `aiBatches` accepts `output`, and results carry each item's parsed `output` or `outputError`. `inboxAdapter` accepts reasoning chunks and keeps them out of the message a contact reads (`reasoning: "metadata"` stores them in `metadata.reasoning`). `vercelSandboxes` takes typed `mounts` for Vercel drives. `vercelConnectCredentials` takes `teamId` and `orgId`, and `channelConfig` supports `"resend"`. The Flags SDK page documents running without `FLAGS_SECRET`.
