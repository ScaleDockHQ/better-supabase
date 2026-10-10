# Changelog

## 0.7.0 (2026-10-10)

- Audit entries record the request and correlation ids of the action that made them, so an app can group an event with the row changes of the same request. `createServer` gives every context a request id (the incoming `x-request-id` when valid, else a new UUID) and a correlation id (the incoming `x-correlation-id`, else the request id), exposes them as `ctx.requestId` and `ctx.correlationId`, sends them as headers on `ctx.db` requests and sets them as the transaction-local `better_supabase.request_id` and `better_supabase.correlation_id` settings for `ctx.sql`. The `requestIds` server option renames the headers, ignores the incoming ones or turns the ids off, and `ContextOptions` takes `requestId` and `correlationId` for jobs.

  The audit module (version 6) reads the ids from those settings, then from the request headers (`requestIdHeader` and `correlationIdHeader` options), keeps only ids of 1 to 128 safe characters through `better_supabase.request_id_or_null`, and indexes `correlation_id` on a managed log. The ids are metadata and never grant access. Run `better-supabase sql sync` and generate a migration to pick up the module change.

## 0.6.0 (2026-10-09)

- The `agents`, `connectors` and `ai-tasks` SQL modules store assistants, their MCP servers and scheduled prompts, and `better-supabase/eve` runs eve agents on Supabase.

  - `createAgents` in `better-supabase/blocks/agents` stores agents with instructions, model, tools, connectors and knowledge scopes, private until published.
  - `createConnectors` in `/blocks/connectors` stores an organization's MCP servers, a grant per user behind a `credential_ref`, and tool lists an admin approves. `createAiTasks` in `/blocks/ai-tasks` runs prompts on a cron.
  - `better-supabase/ai-sdk/agents` adds `createAgentRuntime` and `moderationMiddleware`, and `/ai-sdk/mcp` adds `authorizeConnector`, `connectTools` and `connectAll` (`@ai-sdk/mcp` is an optional peer).
  - `better-supabase/eve` (Node only, `eve` is an optional peer) adds `supabaseAuth`, `credentialAuth`, `supabaseMemory`, `persistSessions` and `routeInbox`.
  - Only the service role sets a task's `next_run_at`, a task's chat must be its user's and its agent the user's own or published, and `drain()` runs every claimed task before it reports the first error.
- The `ai-chat` and `ai-files` SQL modules store AI conversations and their files, and `better-supabase/ai-sdk` connects them to the AI SDK (`ai`, `@ai-sdk/react` and `@ai-sdk/workflow` are optional peers).

  - `createAiChat` in `better-supabase/blocks/ai-chat` keeps chats, a branching message tree, runs, tool approvals, feedback, share links, a model catalog per plan and moderation events; `/blocks/ai-chat/react` adds `useAiChats`, `useAiChatTree`, `useAiModels` and `useAiShare`. Messages use a canonical format (`aiMessageSchema`, `schemas/ai-message-v1.json`, `SPEC_PINS.aiMessage`).
  - `createAiFiles` in `better-supabase/blocks/ai-files` stores uploads in two steps with policies that follow the file row, and versioned documents. `/ai-sdk/files` adds `aiFileDownload`, `saveGeneratedFiles` and `providerFile`.
  - `better-supabase/ai-sdk` adds message converters, AI Gateway helpers and job handlers, `createAssistant` in `/ai-sdk/chat` serves a resumable chat route, and `useAssistant` in `/ai-sdk/react` is `useChat` wired to it.
  - `/ai-sdk/workflow` runs answers as Workflow SDK workflows with `durableChat` and `durableTurn`, and `useDurableAssistant` is the client half. `createAiChat(...).runs` reads run steps, and `createHarnessSessions` reads harness sessions.
  - Harness sessions are read on the server only, the idle-stop job skips a sandbox whose session a turn holds, and the chat list hooks keep every loaded page on a live update and ignore stale responses.
- The AI blocks share one run-state vocabulary, one sandbox table and one set of permission keys. The ai-chat, ai-tasks, ai-providers and memory modules move to version 2; `better-supabase sql upgrade` brings a database installed from an earlier build forward.

  - Runs end `completed`, `failed` or `cancelled` in ai-chat, ai-tasks and workflows. `RunState`, `FinalRunState` and `FINAL_RUN_STATES` from `better-supabase/blocks` name them.
  - `createAiChat(...).runs` has the run lookups, and durable chats read them from the context's `chats`.
  - ai-chat owns `ai_sandboxes`. Harness sessions keep their sandbox there, and `createAiChat(...).sandboxes.idleStopJob` stops chat and harness sandboxes with one claim. Set the idle time with `sql.modules.ai-chat.options.sandboxIdleAfter`.
  - ai-files, knowledge, memory, agents, connectors, ai-tasks and ai-providers check `ai.*` permission keys. ai-chat keeps its `ai_chat.*` keys, and the default roles grant both.
  - `MemoryScope` gains `project`, with `projectId` on namespaces and memory rows.
  - eve sessions release runs with the new statuses, and the jobs page documents jobs cron, workflow schedules and ai-tasks as three scheduling layers.
  - The eve, memory, ai-files, workflow-builder and ai-providers blocks keep their row decoders in `rows.ts`.
- The `ai-cache` and `ai-providers` SQL modules cache model responses and keep each organization's provider keys, and `better-supabase/ai-sdk` meters model calls.

  - `createAiCache` in `better-supabase/blocks/ai-cache` and `cacheMiddleware` in `/ai-sdk/cache` return a stored response or stream for a repeated call, per tenant with a TTL.
  - `createAiProviders` in `better-supabase/blocks/ai-providers` keeps provider keys as `credential_ref` rows with batch and sandbox registries. `byokOptions` and `tenantGatewayOptions` turn them into AI Gateway BYOK options, `trackedSandbox` records sandboxes, and `aiBatches` in `/ai-sdk/batches` runs provider batches from a job.
  - `meterTelemetry` records each call's tokens and cost on the tenant's usage meters, and `spendReconciliation` compares them with the AI Gateway spend report.
- The API keys block (`better-supabase/blocks/api-keys`) issues keys with a checksum, reports their state and authenticates REST routes.

  - Keys end in a CRC-32 checksum, so `verify` and secret scanners reject a mistyped key without a lookup (`parseApiKey`).
  - Keys report `state` (`active`, `grace`, `revoked`, `expired`) and `successorId` (`ApiKeyState`).
  - `withApiKey({ keys })` is a pipeline entry that verifies the key and contributes `ctx.auth`, and `apiKeyClaims` and `apiKeyResolver` take a `claim` shape so the authorization provider reads the key's scopes.
  - `options.scopes: "catalog"` limits scopes to the provider's permission keys, and the provider model refuses the `*` scope unless listed.
- Every SQL module audits its security-relevant actions. Run `better-supabase sql sync`.

  - `ctx.record` takes a required `audit`: one of the shared categories in `AUDIT_CATEGORIES` (`membership`, `access`, `security`, `configuration`, `billing`, `data`, `ai`, `integration`), or `false` for content and status events. With the `audit` module installed, each action writes one audit entry in the same transaction as its outbox event.
  - Settings, flags, billing customers, credentials, connectors, agents, AI provider keys, tool policies and approvals, chat shares, incoming webhooks, webhook secrets, announcements, published workflows, API keys, invitations, the waitlist, SSO domains and SCIM changes now write an audit entry and an outbox event. The access catalog's tables are audited through the row trigger under `access`.
  - `organizations`, `organizations-suspension` and `support-sessions` record through the same path: organization entries move from `organization` to `configuration` or `membership`, support entries from `support` to `security`, and revealed audit details from `audit` to `security`. An adopted log with a category check maps the names with `sql.modules.audit.options.values.category`. `options.auditCategory` is deprecated and still overrides every category of its module.
  - `sql.modules.<name>.audit: false` keeps a module's actions out of the log; they still reach the outbox.
  - `support.started` records the session's tenant, like `support.ended`.
- `audit.sink()` files events under the categories the SQL modules use: `account.*` and `support.*` events get `security`, and a `category` option maps any other event type to one of `AUDIT_CATEGORIES`.
- `createAuditLog({ transport })` in `better-supabase/blocks/audit` lists, reveals and exports the audit log as the caller, and entries record who acted, from where and on what. Run `better-supabase sql upgrade`.

  - `list` (`list_audit_events`) filters by tenant, event type, actor, target, record, category, outcome, source and correlation id, with `search`, a cursor or `offset`, and `count: true`. `reveal(entryId)` returns restricted details and records `audit.revealed`.
  - `export({ format: "ndjson" | "csv" | "ocsf" })` streams the log (CSV takes `columns`, `preamble` and `formatRow`), `exportToStorage` writes it to a bucket, and `record(event)` calls `audit_event`.
  - Entries record actor kind and label, tenant and target labels, `summary`, `request_id`, `correlation_id` and `scope`. Actor and request details are honoured only from the service role and admin connections; `audit_event_trusted` serves an app's `security definer` functions and `options.trustedRoles`.
  - `better_supabase.audit(...)` keeps a table's settings on its trigger, so schema files need no data rows, and `bs_audit_forget_dropped` clears registrations of dropped tables. Adopted logs map their own values with `options.values`, `tenantLabel` and `metadataColumns`.
  - `sql add` writes a pgTAP file per audited table. Doctor BS315 reports tables without an audit trigger and BS322 registrations of missing tables.
- Authorization libraries plug in through a versioned `AuthorizationProvider` (API v1, from `better-supabase/config`) in the `authorization` config key, and the access module's `provider` model renders the provider's SQL templates.

  - Under the `provider` model, the provider's `idsWithFor`, `isPlatformFor` and `canAssignFor` templates let `can_user()` and `member_can()` answer for any user, the invitations module check the inviter again at accept, and the notifications module filter recipients by their read permission. `sql.modules.access.functions.canAssignFor` defines `can_assign_as` under the provider and custom models.
  - `sql.modules.access.disabled` defaults to the provider's `suspension` rows. `disabled.tenant` and `disabled.user` also take an active-row shape (`{ table, id, disabledAt, status, active }`), where a missing row counts as disabled.
  - `testAuthorizationProvider` from `better-supabase/testing` checks a provider, and `templateFunctions` from `better-supabase/sql` lists the functions a template calls. Doctor BS214 compares a Storage or Realtime policy's scope with the provider's `permissions[].scopes` and reports keys not marked `sqlComplete: true`.
  - The CLI rejects a provider with an unknown scope or a parent cycle, a tenant scope without an `idType` (`SCOPE_ID_TYPES`), a `decidingColumns` entry that isn't `schema.table.column`, or another `apiVersion` (`providerApiProblem`). `testAuthorizationProvider` also checks that `requires` lists every function a template calls and that the token hook claims don't overlap.
  - Without `canAssign`, only the service role assigns roles under the `provider` model. Doctor BS411 names each installed module missing a template it needs.
  - `functions.permissionsFor` fills `member_permissions` and `permission_claims`, and `functions.canApprove` with `approvals.distinctApprover` decides AI tool approvals. Bucket and topic policies take `sql: "provider"` to use the provider's templates, `createAgentRuntime` takes a `toolApproval` hook, the claims config has a `memberships` path (`claimPaths`), and the `apiKey` caller carries `createdAt` and `createdBy`.
  - **Breaking:** every PermDock-specific setting and export is removed. `sql.modules.access.model: "permdock"` becomes `"provider"`, `entitlements.permdock` becomes `entitlements.memberships`, bucket and topic `permdock` policies become `access` policies with `scope` and `sql` templates, `permdockVerifier` and the `permdock` claim option of `apiKeyResolver` become the provider package's job and the neutral `claim` option, and doctor reads the provider instead of `permdock.config.ts`, the manifest and the catalog. The [0.5 to 0.6 guide](https://bettersupabase.com/docs/migration/0.5-to-0.6) has the old-to-new table.
- The billing block (`better-supabase/blocks/billing`) runs a tenant's Stripe subscription over the Stripe Sync Engine and gives platform staff typed lists across tenants.

  - `changePlan`, `cancelAtPeriodEnd`, `invoices`, `paymentMethods`, `voidInvoice`, `customerDetails`, `updateCustomer` and tax ids (`StripeTaxId`).
  - `options.plans` points at your plan catalog with price `variant`s, and `checkout` merges `params` deeply.
  - Staff with `viewAll` read `allSubscriptions`, `allInvoices` and `allCustomers`, also as `billing_platform_*` SQL functions.
  - `StripeSource` accepts a function that returns a client, and `ensureCustomer` is idempotent per organization.
- Blocks can be extended without forking them: add your own columns and type them, steer methods with hooks, wrap the transport and add methods.

  - `options.extraColumns` on the `organizations` and `profiles` SQL modules adds your own columns to the managed table, copies them on writes and returns them from reads. `list_my_organizations` returns the attribute and extra columns in a new `attributes jsonb` column.
  - A Standard Schema `fields` option on `createOrganizations` and `createProfiles` types those columns, parses them on read and turns a bad write into a `validation` error. `createNotifications` parses stored `data` with its type's schema on `get`, `list` and `page`, so `item.data` narrows on `item.type` (`NotificationOf`); data the schema rejects fails with the hint `NOTIFICATION_DATA_INVALID`.
  - A `hooks` option on those blocks, and on `createBlocks` keyed by block name, runs `before` hooks that refuse a call with a `DbError` or replace its arguments, and `after` hooks that observe a copy of the result. `withBlockHooks` does the same for any block.
  - New SQL hooks: `before_organization_update`, `after_organization_update`, `before_profile_update`, `after_profile_update` and `before_notification_send`.
  - `wrapTransport` runs versioned `BlockTransportMiddleware` around every block call, checked by `testBlockTransportMiddleware` in `better-supabase/testing`, and `extendBlock` adds methods and refuses to redefine one.
- `createBlocks` in the new `better-supabase/blocks` subpath builds several blocks from one set of options, and the blocks share their helpers, option names and page shape.

  - `createBlocks({ transport, service, schema, credentials, events, audit }, factories)` builds the blocks you pass and wires their siblings: the AI files block into knowledge, `credentials` into connectors, ai-providers and the workflow builder, notifications into ai-tasks (with `aiTaskNotification`), and block events into an audit sink. The subpath also exports `rpcTransport`, `sqlTransport` and the `BlockOptions` and `CursorPageOptions` types.
  - `audit.sink()` returns an `EventSink` that records each CloudEvent in the audit log, with its type, subject, tenant and data. `createServer({ audit })` sends `account.suspended`, `account.unsuspended`, `account.deleted` and `account.sessions_ended` from `suspendAccount`, `deleteAccount` and `endSessions`, and forwards `support.denied`; a failing sink never changes a result.
  - Block lists page with `{ limit, cursor }`, which replace `size`, `before` and `after`.
  - Notifications, organizations, profiles and outgoing webhooks take `mappers` instead of `errorMappers`.
  - `CredentialProvider` gains an optional `set(ref, value, { subject, description })`, which Vault implements and the workflow builder uses. `credentialRouter(providers)` serves several providers as one, and `revokeIfConfigured(provider, ref, { subject, tenant })` revokes only when a provider is configured, can revoke the ref and the ref is in the tenant.
  - `Embedder`, `EveDocumentBackend`, `AiTaskRunner`, `GraphCompiler` and `BuilderStarter` take an optional `apiVersion: 1`; a block refuses another version. `better-supabase/testing` adds `testEmbedder`, `testEveDocumentBackend`, `testAiTaskRunner`, `testGraphCompiler` and `testBuilderStarter`.
  - The block row decoders moved into the core and every block uses the same ones; `better-supabase/blocks/knowledge` no longer exports `vectorLiteral`.
- The CLI finds its config from any package in a workspace, pg-delta is the default diff engine, and doctor reports each problem once.

  - `better-supabase.config.*` and `supabase/config.toml` are found in the working directory or a parent up to `.git`, and `init` at a workspace root asks for the package or takes `--package <dir>`.
  - `init` turns on `[experimental.pgdelta]` unless it is set to `false`, and doctor BS316 warns projects still on migra. `better-supabase config` prints the resolved config.
  - Doctor skips findings the performance advisor already reports, runs splinter with the `[api] schemas`, and adds BS222 (`int8` decoded as `number`), BS317 and BS318 (statements pg-delta can't order) and BS319 (SQL that alters a reserved role). `tables.<name>.serviceRole: true` marks a server-only table for BS106 and BS107.
- `better-supabase/vue`, `/solid` and `/svelte` bind the browser client with the features of `better-supabase/react`, and new hooks and query helpers cover forms, uploads and optimistic updates.

  - `useAction` and `useActionForm` call a `bs.action()` and track `pending`, `data`, `error` and `fieldErrors`. `better-supabase/react` adds `usePresence`, `useSignIn`, `useSignOut`, `useDebouncedSearch`, `useSignedUrl` and `useUpload`, and `upload()` takes `onProgress`.
  - `better-supabase/query` adds `optimistic` with rollback, `{ maxPages }` for infinite queries and `escapeLike`, and `createQueries` takes a `scope`. `better-supabase/tanstack-db` adds `collectionOptions`.
  - `clearOnUserChange` also resets queries when the token changes tenant, role or assurance level. `bindClient` returns `dispose()`, and `liveQuery` rejoins a failed channel with backoff.
- `gen` writes tighter types from CHECK constraints, documents tables in the generated validators and can run from a metadata document. Run `better-supabase gen`.

  - A nullable column a CHECK requires is typed not null, and `tables.<table>.insertOptional` marks columns the database fills on insert. `relations: { nullableUnderRls: true }` types to-one relations to RLS tables as nullable.
  - `zod()`, `valibot()` and `jsonSchema()` add titles, descriptions and examples from comments, and enforce bounds from simple CHECK constraints.
  - The generated module exports `WhereOf<"table">`, `OrderByOf<"table">` and `OrderTermOf<"table">`, and the metadata module is about 40% smaller.
  - `gen --metadata <path|->` generates from a `GeneratorMetadata` document for `@supabase/typegen`, and `doctor --metadata` checks it.
  - Generators declare `apiVersion: 1` and receive `model`. `gen` deletes files it no longer writes, fails on name collisions, and `gen --watch` reloads the config and retries.
  - **Breaking:** colliding `_by_` relations are named by every key column (`customerByCustomerOrganization`) instead of ending in `_`, and view copies are no longer relations. Keep an old name with `tables.<table>.relations`.
  - **Breaking:** `@supabase/postgrest-typegen` is an optional peer; install it for `gen`, `introspect` and `doctor` with `pnpm add -D @supabase/postgrest-typegen@0.4.0`.
  - **Breaking:** a `GeneratorInput` built by hand needs a `model`.
- The comments and attachments blocks (`better-supabase/blocks/comments`, `/blocks/attachments`) store threads and files on any subject with per-subject permissions.

  - `options.subjects.<type>` takes `permissions: { read, create, moderate }`, `cascade`, and `label`, `path` and `readableBy` for notifications; a mentioned member is notified only when they may read the subject.
  - Comments keep a rich-text `document` (`mentionsOf`, `options.documentSchema`), expand `options.mentionGroups`, and have `copy()`, `history()` and `counts()`.
  - Attachments take a `bucket`, `allowedMimeTypes` and `tenant: false` per subject, keep `metadata`, and have `put(attachment, file)` and `read(id)`. A malware scan gate works for any bucket (`object_clean(bucket, path)`, `createObjectScanner`, `options.scanBuckets`).
- Errors map to typed messages and result libraries, plugins behave the same whoever wrote them, and each definition keeps its own state.

  - `createErrorMessages(messages)` needs a message for every `DbError` kind. `toBetterResult` returns better-result's own `Result<T, E>` when that is the expected type, and `defineBetterResultErrors` maps kinds to `TaggedError` classes. `P0002` maps to `not_found`.
  - Plugins get `enforce: "first"`, a mutation `intent`, `scopes`, and a `context` hook per `connect()`, so two definitions in one process no longer share a tenant. Hooks receive the caller's `signal`, and `db.$withoutPlugins({ keep })` keeps named plugins.
  - `defineSupabase(schema, { temporal })` takes the `Temporal` namespace without patching `globalThis`, and `diagnostics: true` logs a record without tokens or row values for every query.
  - **Breaking:** `DbError` gains the kinds `quota_exceeded` (429), `max_affected` (400) and `unsupported` (501). An exhaustive `switch` over `DbError["kind"]` needs the new cases.
- `better-supabase/credentials` resolves third-party tokens from a `credential_ref`, and `better-supabase/streams` stores resumable output for chats, workflows and agents.

  - `vaultCredentials()` keeps secrets in Vault through the `credentials` module and verifies inbound signed requests. `createServer` takes a `credentials` provider as `ctx.credentials`, `subjectFor(ctx)` gives the subject, `better-supabase/vercel-connect` adds `vercelConnectCredentials()`, and `testCredentialProvider` checks other providers.
  - The `streams` module keeps ordered chunks with idempotent appends and a cancel flag, used by `postgresStreamStore`, `teeToStore`, `writeToStore` and `resumeFromStore`. `better-supabase/streams/redis` adds `redisStreamStore` (`redis` is an optional peer), and `testStreamStore` checks other stores.
  - A tenant's `credential_ref` carries `tenant` (`tenantCredentialRef`, `credentialRefInTenant`): connectors, AI providers, the workflow builder and MCP refuse a ref from another tenant with `CREDENTIAL_REF_FOREIGN`, Vault stores tenant secrets as `tenant/<tenant>/<secret>`, and `vercelConnectCredentials` refuses a tenant ref for the app subject.
- The data-lifecycle block (`better-supabase/blocks/data-lifecycle`) exports, anonymizes and purges a tenant's or a user's data across every module table.

  - Modules declare their tables, so exports and purges cover every installed module, and `options.autoTables` adds a schema's tenant tables. Exports leave out keys, token hashes and secrets.
  - The purge retries referenced tables, stops with `ORGANIZATION_PURGE_BLOCKED` when stuck, and deletes the tenant row last. `createOrganizationPurger({ buckets })` takes path prefixes (`PurgeBucket`).
  - `options.anonymize` rules anonymize rows after a retention period (`anonymizeDue()`), and `createDataExporter` takes `format: "csv"`.
- Block events follow one contract. Run `better-supabase sql sync` and `better-supabase codemod 0.6`.

  - Every type is `<entity>.<past_tense_verb>`. Renamed: `ai_chat.message.completed` to `ai_chat_message.completed`, `inbox.conversation.*` to `inbox_conversation.*`, `inbox.message.received` to `inbox_message.received`, `incoming_webhook.rotated` to `incoming_webhook.token_rotated`, `workflow.alert` to `workflow_alert.triggered`, `workflow.run.*` to `workflow_run.*` and `data_export.ready` to `data_export.completed`.
  - `BLOCK_EVENT_RENAMES` from `better-supabase/events` maps the `org.*` types to `organization.*`, and the 0.6 codemod rewrites string literals that name a renamed type.
  - `BlockEventMap` types every event a SQL module records. Each module declares its events in `NAMES.events`, and `ctx.record` throws for an undeclared type, a subject that is not a kebab-case plural, a missing payload key or a retried event without an idempotency key.
  - Support events carry a camelCase payload with `organizationId` under `support-sessions/<id>`. Push, waitlist and audit subjects are `push-devices/`, `waitlist-entries/` and `audit-entries/`. SCIM events name `scimUserId` or `scimGroupId`.
  - `notification.created`, `webhook.disabled` and the workflow events carry `organizationId`. `notification.created`, `webhook.disabled`, `attachment.scanned`, `inbox_message.received`, `data_export.completed`, `data_export.failed` and `organization.purged` have idempotency keys.
  - `notifications.sink({ map })` turns outbox events into notifications, keyed by the event id.
- Adapters for more server frameworks, typed structurally, with the guards and actions of the Next.js adapter. They replace the `@supabase/server` framework adapters, which upstream removes on 2026-12-01.

  - New subpaths: `better-supabase/tanstack-start`, `/sveltekit`, `/react-router`, `/h3`, `/h3/v1`, `/elysia`, `/node` (`toExpress`, `toFastify`, `toKoa`), `/nestjs` (`@nestjs/common` is an optional peer), `/astro`, `/nuxt` and `/solid-start`. `toHono`, `toEdge`, `toOrpc` and `toExpo` bridge the existing adapters.
  - Each factory puts `db`, `bs`, `auth`, `tenant` and `session` on the request, with `bs.require()` and `bs.action()`; every guard takes `roles` and `roleClaim`. The edge gets `bs.routes({ "GET /customers/:id": handler })` with typed `ctx.params` (`RouteParams`), oRPC gets `bs.authed()`, and `createMcp` takes `requiredRoles`.
  - `handle()`, `extendServer`, `flushEvents` and `resolveToken` build an adapter on the shared request path, checked by `testAdapter`. `withServerTiming()`, `withDbStats()` and `tagCache` cover timing headers, database budgets and tag caches.
  - **Breaking:** `createEdge`'s `cors` option runs `withCors` from `@supabase/middleware/cors`. A preflight needs `Access-Control-Request-Method` (other `OPTIONS` requests reach the handler), and an allow-list adds `Vary: Origin`. `corsConfig(options)` returns the config.
- The `inbox` SQL module and `better-supabase/blocks/inbox` add a shared support inbox per organization, and `better-supabase/chat-sdk` runs Chat SDK bots on it (`chat` `>=4.41 <5` is an optional peer).

  - The inbox stores contacts, conversations with assignment, teams, snoozing and bot handoff, messages and notes, read receipts, deliveries and attachments, with `purgeContact` for data subject requests. `useInbox`, `useConversation` and `useInboxWidget` in `/blocks/inbox/react` stay current over private Realtime topics.
  - `createSupabaseState` is a `StateAdapter` on the `chat-sdk-state` module, `inboxAdapter` answers in the in-app widget, and `webhook`, `inboundHandler`, `deliver`, `maintain` and `createChatInstallations` record Slack, WhatsApp, Messenger and SMS conversations. `testChatState` checks any `StateAdapter`.
- Invitations can be edited, answered from an in-app inbox and sent for platform roles under the `provider` model. Run `better-supabase sql upgrade`.

  - `update_invitation` (`organizations.updateInvitation`) changes an open invitation and emits `invitation.updated`; it refuses an expired one, so call `resend_invitation` first.
  - `my_invitations()` lists the signed-in user's open invitations, and `acceptInvitationById` and `declineInvitationById` answer them. Invitations carry `extra` from the `invitation_preview_extra` hook, `createdAt`, `organization` and an `inviter`.
  - `options.platformRoles` names the platform role table, with `through`, `canAssign` and `canAssignFor` checked at invite and accept. `through.where` is required when its table is also `roleThrough`'s, and `bs_role_scope` refuses other roles on direct writes (`PLATFORM_ROLE_SCOPE`).
  - **Breaking:** accepting or updating an expired invitation fails with the hint `INVITATION_EXPIRED` instead of `INVITATION_INVALID`, which now means unknown, accepted, declined or revoked.
  - **Breaking:** `Invitation` has a required `inviter` field (`null` without the profiles module), and the `invitation_preview_extra` hook also runs for invite, resend, update and `my_invitations`.
- Jobs run as the user who enqueued them and report queue health, and `better-supabase/blocks/jobs` adds leases and rate limits. Run `better-supabase sql upgrade`.

  - `bs.forContext(job.context)` returns repositories as the context's user and tenant, so RLS applies in the handler. It keeps a read-only support session read-only, and `claimsFor(userId, context)` rebuilds hook claims.
  - `jobs.stats()`, `listDead()` and `retryDead()` serve admin pages, and `enqueue` takes `dedupe: "waiting"`.
  - Under `scheduler: "drain"`, schedules record a tenant (`listSchedules`, `unscheduleAll`), `ensureSchedules` keeps a named set in step, `drainRoute` takes `monitor` hooks, and `devDrain` drains locally.
  - `withLease(sql, key, fn)` holds one holder per key. `hit_rate_limit(scope, key)` and `createRateLimit().check()` limit any key, and `rateLimited(decision)` answers 429 with `Retry-After`.
  - **Breaking:** `begin_idempotent` returns a `holder`, and `complete_idempotent` and `release_idempotent` (`createIdempotency().complete` and `release`) take it and return false after another caller took an expired key over.
- Kits are now blocks, and every feature module lives under `better-supabase/blocks/<name>`. There are no aliases; the [0.5 to 0.6 guide](https://bettersupabase.com/docs/migration/0.5-to-0.6) lists every rename.

  - **Breaking:** subpaths move. `better-supabase/orgs` is `better-supabase/blocks/organizations`, and `better-supabase/jobs`, `/notifications` and `/webhooks` are `better-supabase/blocks/jobs`, `/blocks/notifications` and `/blocks/webhooks`. `createOutbox` and `outboxCloudEvent` move to `better-supabase/blocks/outbox`, and `purgeAuditLog` to `better-supabase/blocks/audit`. `hasEntitlement`, `EntitlementKey`, `entitlementMembers` and `ENTITLEMENTS_UPDATED` move to `better-supabase/blocks/entitlements` (out of `server`, `next`, `ssr`, `react` and `jobs`), and `useNotifications` moves from `better-supabase/react` to `better-supabase/blocks/notifications/react`.
  - **Breaking:** `sql.kit` and the `kits` key merge into `sql.modules`, an object keyed by module name whose values are the module settings (a list of names still works).
  - **Breaking:** `Kit*` names for features are `Block*` (`BlockEvent`, `onBlockEvent`, `forwardBlockEvents`), and `Kit*` names for SQL modules are `Module*` (`ModulesConfig`, `ModuleConfig`, `renderModules`, `modulePermissionKeys`). `org` is spelled out: `createOrganizations`, `Organizations`, `organizationLogoBucket`, and the `organization.*` event types replace `org.*`.
  - **Breaking:** in SQL, `member_org_ids`, `has_org_role` and `org_member_role` are `member_organization_ids`, `has_organization_role` and `organization_member_role`, the organization functions take an `organization` parameter, `better_supabase.kit_modules` is `better_supabase.modules`, and module files carry `-- @bs-module` and `-- @bs-module-data` markers. Run `better-supabase sql sync`, the schema diff and `better-supabase sql data` to move a database over.

  `list`, `storage`, `realtime` and `events` keep their subpaths. The list, storage and realtime pages move to `/docs/platform`, and the events page to [`/docs/standards/events`](https://bettersupabase.com/docs/standards/events).
- The `knowledge` and `memory` SQL modules give agents retrieval and long-term memory; both require `vector-search`.

  - `createKnowledge` in `better-supabase/blocks/knowledge` stores documents scoped to an organization, agent, project, chat or user, chunks them with embeddings and a `tsvector`, and searches with reciprocal rank fusion. With `jobs` installed new documents are enqueued for embedding; `ingest.file` reads an `ai-files` upload.
  - `createMemory` in `better-supabase/blocks/memory` keeps core memory files under `/memories`, archival facts and one embedding per chat message, plus versioned `memory.documents`.
  - `better-supabase/ai-sdk/embeddings` adds `embedWith`, `supabaseEmbed`, `rerankWith`, `searchTool` and `toSourceParts`, and `/ai-sdk/memory` adds `memoryTool`, `anthropicMemory`, `recallTool`, `withMemory` and the `extractMemories` job handler.
  - An item rewritten while it is being embedded stays pending, `set_memory_embeddings` writes a batch, bad vectors fail with `EMBEDDING_INVALID`, and knowledge `drain` tries each document `attempts` times (3) before marking it failed.
- `better-supabase/mcp/sdk` serves MCP servers built on the official SDK (`@modelcontextprotocol/server` 2.3 or later, an optional peer), and `createMcp` works on hosted Edge Functions.

  - `createMcpAuth(betterSupabase, { resource })` verifies Supabase tokens locally as an `OAuthTokenVerifier`, serves the RFC 9728 metadata and answers 401 and 403 challenges. `withBetterSupabaseMcp(server, auth)` gives every tool callback `db`, `auth` and `bs`.
  - On Edge Functions the `resource` comes from the function slug. Both servers answer CORS preflights (`allowedOrigins`) and take `requiredRoles` and `waitUntil`.
- Expo and React Native get a server adapter, a native client, local SQLite executors and push notifications.

  - `better-supabase/expo`: `createExpo(betterSupabase)` gives Expo Router loaders, API routes and `+middleware.ts` the verified caller; `better-supabase init expo` writes it.
  - `better-supabase/client/native`: `createNativeClient(betterSupabase, supabase)` binds repositories without `@supabase/ssr`, `secureStorage` and `largeSecureStorage` keep sessions in the keychain, and `autoRefreshOnForeground`, `syncQueryWithApp`, `persistQueryCache`, `uploadFromUri` and `handleAuthDeepLink` cover the app lifecycle. `better-supabase/react/native` adds `useOAuth`, `useAuthDeepLinks`, `useProtectedRoute` and `AuthGate`.
  - `better-supabase/powersync`: `powersyncExecutor(db)` runs the same repositories on PowerSync's SQLite, `createUploadConnector` replays queued changes and `syncWithAuth` clears data on a user change; `/powersync/react` adds `useWatch`, `useSyncStatus` and `useConflicts`. `better-supabase/expo-sqlite` adds `expoSqliteExecutor(db)`.
  - The `push` module and `better-supabase/blocks/push` store device tokens and send through the Expo Push API (`registerDevice`, `expoPush`, `expoPushChannel`).
- The Next.js adapter authorizes actions and Server Components, signs out ended sessions and scopes cache tags to a tenant.

  - `bs.action()` and `bs.route()` take `requireTenant` and `authorize(session, input)`, and `bs.require(options)` refuses a Server Component caller with `unauthorized()`, `forbidden()` or `notFound()`.
  - `bs.proxy(request, { endedSession })` asks Auth whether the session still exists and clears the cookies when it doesn't, and `expiredPrefetch: "render"` renders a prefetch with an expired token signed out.
  - `bs.cacheTag`, `bs.cacheTags` and `bs.cached` take `{ tenant }`, so a mutation in one tenant no longer revalidates other tenants' reads, and `bs.context({ tenant })` takes the tenant from route params.
  - Mutations outside a Server Action expire tags with `{ expire: 0 }`, so a read after a write in a route handler is fresh (`nextCache({ revalidate })` keeps `"max"`).
  - `useSessionChange` refreshes the session before an organization switch re-renders, and `tenantOf(session)` reads the active tenant.
  - **Breaking:** the `next` peer range is `>=16.3 <17`, because `createNext` awaits `io()`. Upgrade Next.js first.
- The notifications block reads more of the inbox, hydrates a page in one call and reports who received a send. Run `better-supabase sql upgrade`; a custom-mode module implements the new signatures.

  - `get(id)`, `page({ offset })`, `markUnread`, `subscriptions()` and `preferences()` are new, and `list` filters by subject type, search and read, resolved or dismissed state.
  - `hydrate(items)` loads what `render` needs for a page, and `include: ["actor"]` adds each actor's profile.
  - `send` takes `watchers: false` and `exclude`, and `subscribe({ ifAbsent: true })` auto-follows without overriding a member's choice.
  - **Breaking:** `markRead`, `markUnread`, `dismiss` and `resolve` return `{ count, items }` instead of a number, and their SQL functions return `jsonb`.
  - **Breaking:** `send()` returns `{ id, recipients }` instead of the id, and `onSent` and `notification.created` get the recipients. It calls `send_notification(jsonb)`; `notify(jsonb)` still returns the id.
- Organizations can suspend members, route deletion through data-lifecycle and give platform staff admin rights, and profiles store an avatar path. Run `better-supabase sql upgrade`.

  - `suspend_member` and `resume_member` (`organizations.suspendMember`, `resumeMember`) keep a member's role but drop its permissions through the memberships table's `disabled_at`; they refuse the caller, the last owner and higher members. `transfer_ownership` refuses suspended or disabled new owners.
  - `options.deleteMode: "lifecycle"` sends deletion through data-lifecycle's grace period, and `"none"` writes no delete function.
  - `permissions.updatePlatform`, `deletePlatform`, `updateRolePlatform` and `removeMemberPlatform` let platform staff manage any organization. `options.assignmentGuard: "external"` drops the module's role guard, which now checks only client writes.
  - Profiles get `avatarPath`, `usernameFrom` takes several keys with a separator, and `readPolicy: { platform }` lets staff read every profile. `reserved-slugs` takes `slugs`, `minLength` and `maxLength`.
- The outbox (`better-supabase/blocks/outbox`) hands consumers the raw rows and moves failing events aside. Run `better-supabase sql upgrade`.

  - `outbox.consume(consumer, handler)` passes `OutboxEvent` rows (`OutboxHandler`), and `relayRoute` accepts such a handler.
  - A failing consumer backs off (`maxBackoff`), and after `maxAttempts` failures an event moves to `outbox.deadLetters(consumer)`. `purge` takes `{ ignoreIdle }`, and `createOutbox` takes a `BlockTransport`.
- Realtime topics support presence, write their own policies and build triggers from parent rows.

  - `defineTopic` takes `presence`, and subscriptions get `track`, `untrack`, `members()` and `onPresence`.
  - `realtime.policies: { from, output }` writes every topic's `realtime.messages` policies on `sql sync`, with a `--check` drift test.
  - `topic.triggerSql()` takes lookups through parent rows, an `event` name and a custom `payload` (`TriggerLookup`).
  - `realtime.users` gives live queries on a table a per-user topic, and `useBroadcast` works with a plain supabase-js `client`.
- **Breaking:** 0.6 removes the deprecated aliases 0.5 kept for one minor. A support token whose `act` has `session_id` but no `kind` is refused as `invalid-chain`. The audit module (version 5) drops the read-only `better_supabase.audit_log` view; read `better_supabase.audit_events`. `maxUrlLength` is gone from `defineSupabase` and `postgrestExecutor` (use `urlLengthLimit`), `scopes` from the MCP server options (use `advertisedScopes`), and `createInbox` and the `Inbox*` types from `better-supabase/blocks/jobs` (use `createWebhookInbox` and `WebhookInbox*`). `better-supabase codemod 0.6` now renames the `Kit` and `Org` exports and `maxUrlLength`, and lists imports from the moved subpaths for review.
- Repositories read with more filters and sorts, split long `in` lists instead of failing, and count pages cheaply by default.

  - `findOnly({ where })` returns the one matching row, `null` for none and `multiple_rows` (409) for more.
  - `where` takes json `path` filters (`JsonPathOps`), `match` and `imatch` regular expressions, and json containment with arrays. Reads longer than `urlLengthLimit` (6000) split along their longest `in` list.
  - `orderBy` sorts by a to-one relation's column, `aggregate()` sorts groups by `_count` or a measure (`AggregateOrderBy`), and `paginate({ offset, limit })` returns an offset window. `defineReadSet` takes `auth.uid`.
  - **Breaking:** list queries count with `count: "planned"` by default; pass `count: "exact"` for the old behaviour.
  - **Breaking:** cursors record the table and sort, so cursors made before 0.6 and arrays from `encodeCursor()` fail with `Invalid cursor`. Start again with `after: null`.
- Writes take conditions, return rows from bulk calls and cap how many rows they change.

  - `update(key, patch, { where })` returns `not_found` for a row that doesn't match, `expect` takes `where` operators, and `updateMany` and `deleteMany` take `returning: true`.
  - `updateMany` and `deleteMany` take `maxAffected`; a write matching more rows fails with `max_affected` and changes nothing. It needs PostgREST 13 (set `postgrestVersion: "12.2"` on older servers), and the rules plugin's `strict()` preset requires it.
  - Every call takes `timeout` and `retry`, `createMany` and `upsertMany` take `defaultToNull`, and mutations take `count: "planned"`.
  - **Breaking:** `deleteMany` and `updateMany` refuse a `where` that filters nothing. Pass `allowAll: true` to `updateMany` to update every row.
  - **Breaking:** an update whose `data` sets no columns returns `invalid_request` instead of `not_found`.
  - **Breaking:** a `*` in `like` and `ilike` patterns is a literal character; use `%`.
- `db.$rpc` is typed per overload, accepts `null` arguments and runs over the Postgres executor. Run `better-supabase gen`, then `better-supabase codemod 0.6`, which lists every `$rpc` call to review.

  - `gen` keeps every overload of a function as a union in `Functions`, and `$rpc` picks the overload by the argument names the call passes. Arguments are typed `T | null`.
  - `postgresExecutor` implements `rpc()`, so requests over a direct connection (an API key, a job) call functions too.
  - `rpcTransport` and the jobs block's `pgmq_public` backend accept a typed `SupabaseClient<Database>` without a cast.
  - **Breaking:** `gen` types function results as nullable: scalars, `setof` scalar elements, a single row and each `returns table` column are `| null`. Set `functions.<name>.notNull` in `better-supabase.config.ts` to `true` or to the columns that are never null.
  - **Breaking:** `$rpc` returns rows of a table and `returns table` records in the configured casing with the configured codecs, like repository reads, typed as the model row. Delete hand-written key mapping around those results, or pass `{ raw: true }` for what PostgREST sent.
- New SaaS blocks, each an SQL module with a subpath: `better-supabase/blocks/api-keys`, `/audit`, `/settings`, `/usage`, `/billing`, `/flags`, `/comments`, `/attachments`, `/data-lifecycle`, `/sso`, `/onboarding`, `/waitlist`, `/announcements` and `/push`. Add one with `better-supabase sql add <name>`; `stripe` is an optional peer that only billing and usage load.

  - SSO serves SCIM 2.0, flags evaluate rollouts in SQL and through an OpenFeature-shaped provider, and `SPEC_PINS` gains `ocsf`, `openfeature` and `scim`. Under the `provider` model, SSO and waitlist roles go through `roleThrough` and need `can_assign` (`SSO_ROLE_FORBIDDEN`, `WAITLIST_ROLE_FORBIDDEN`), and `join_waitlist` always answers `status: "waiting"` to clients.
  - Blocks take `ctx.postgres` from `@supabase/server`, `withBlock(key, create)` puts a block on the context, and every block takes `temporal` and a `problem` option (`ProblemFormat`) for error bodies.
  - New event types cover organization domains and deletion, `billing.*`, comments, attachments, data exports and `waitlist.approved`.
  - **Breaking:** the server's `auth.kind` gains `"apiKey"`, so an exhaustive `switch` over it needs the new case.
- `withBetterSupabase(server, options)` from `better-supabase/server` is one `@supabase/middleware` entry that resolves the caller and contributes the request's database handles, and the server gains session and account helpers. `better-supabase` depends on `@supabase/server` `^1.9.1`.

  - The entry reads a bearer token, then the session cookie, enforces `allow`, `aal` and `scopes`, and contributes `bs`, `db`, `sql`, `tenant` and the keys `withSupabase` writes. `server.context(request)` runs the same entries once per request. `createServer(betterSupabase, { db: { timeout, retry, urlLengthLimit } })` tunes its requests.
  - Session cookies support the `@supabase/ssr` 0.12 `tokens-only` encoding (`encode: "tokens-only"`, doctor BS412 for mismatches), and `cookieScopes` and `clearSessionAtScopes` expire cookies an earlier deploy set.
  - `sessionStatus` and `clearSessionCookies` run the ended-session check in any proxy. `endSessions(sql, userId)` and `suspendAccount(admin, sql, userId, { suspended })` end sessions and ban a user, and `deleteAccount` is exported on its own and returns the database's error, such as `ORGANIZATION_OWNER_REQUIRED`, with the `sql` option.
  - An early refresh that hits a network failure keeps the user until the token expires, and the `otel` plugin records `db.$rpc` calls as spans.
  - **Breaking:** the leaf entry `withBetterSupabase(betterSupabase)` that ran after `withSupabase` is renamed `withBetterDb(betterSupabase)`. Replace it, or drop `withSupabase` and use the new `withBetterSupabase(server)`.
- The settings block has a `platform` scope for product-wide settings, and feature flags can be managed from an admin page.

  - `defineSettings({ platform })` adds `client.platform`; each key names the permission that changes it and who reads it, and only listed keys can be written.
  - `createFlagAdmin({ transport })` lists, saves and deletes flags and sets overrides for staff with `flags.manage`. `tenant_ids_with_flag(key)` is the policy form of `flag_enabled`, `createFlagsProvider` works over the Data API, and `flagContext` reads a `memberships` claim.
- SQL modules call each other through shared helpers and declare the modules they work with, and fewer modules pull in others they only use when present. Run `better-supabase sql sync`.

  - `ModuleContext` gains `record`, `notify`, `enqueue`, `entitlements`, `broadcast`, `can` and `staff`. Each returns a statement or expression that is valid without the other module, so a module installs alone and calls the other one once it is installed.
  - `SqlModule.integrates` lists the optional modules a module works with. `ctx.installed` and `ctx.of` throw for a module it neither requires nor lists, `better-supabase sql list` prints "works with", and the blocks overview has the full matrix.
  - `inbox` no longer requires `jobs` or `streams`: without `jobs` it queues no bot or delivery jobs. `workflows` no longer requires `jobs`, and `ai-cache` no longer requires `tenant`.
  - `webhooks-in` requires `updated-at`, which its trigger uses.
  - `support.ended` records the session's tenant in the audit log and the outbox, like `support.started`.
  - `sql.modules.jobs.schema` is rejected: the jobs module always installs in `better_supabase`, so a schema only pointed the modules that call it at missing functions. Functions of the `access` module are always called in `better_supabase`, whatever `sql.modules.access.schema` sets for its tables.
- SQL modules can be called over the Data API without exposing their schema, and land their extensions and event triggers in migrations. Run `better-supabase sql sync` and create a migration for the new function bodies.

  - `sql.modules.<module>.api` writes `security invoker` entry points for the functions apps call into a schema, and `rpcTransport(supabase, { schema: "api" })` calls them there. Doctor BS312 points at the option.
  - `sql add`, `sync` and `upgrade` write the modules' extensions into a `<stamp>_better_supabase_extensions.sql` migration, and data files repeat extensions and event triggers so pg-delta plans need no hand edits (doctor BS321, BS323).
  - The `ensure-rls` module enables row level security on every new table outside the Supabase-managed schemas.
  - A write that breaks a `jsonb-schemas` schema fails with a `validation` error whose `issues` name the column.
  - `sql.modules.sessions.options.policies` writes a restrictive `bs_session_active` policy on every table, and doctor BS320 reports tables without one.
  - The `grants` module keys functions by signature, takes column privileges such as `"update(title, body)"`, and derives grants from permissive policies with `options.fromPolicies`.
  - Policies check tenant permissions once per statement, module functions pass `supabase db lint`, and module actions follow a renamed sibling key.
  - **Breaking:** `grants` writes the complete privilege set of each entry in `expose`, so a table loses privileges it doesn't list, including `truncate`, `references` and `trigger`, on the next sync.
- `defineBucket` covers what Storage added in supabase-js 2.117, takes several path layouts and reports bad paths as a `Result`.

  - `versioning` and `lifecycle`, applied with `bucket.apply(client)` and checked by doctor BS302. Connected buckets list `versions`, take a `versionId`, and have `removeVersions`, `purgeCache`, `copy` and `move`. `defineVectorBucket` and `defineAnalyticsBucket` declare the new bucket kinds.
  - `path: [current, older]` accepts several templates, and `{...rest}` matches any depth. `defineBuckets({ ... })` registers definitions by id for rows that store a bucket id (`byId`, `resolve`, `connectStored`).
  - Policies from `.sql()` use the name index, `sweep()` removes only objects matching every `within` value, and `replace()` checks `previous` against the tenant.
  - **Breaking:** a bucket definition's `path(values)` returns a `Result<StoragePath>` instead of throwing.
  - **Breaking:** a connected bucket's `publicUrl()` returns a `Result<string>`. `better-supabase codemod 0.6` lists both kinds of call.
- The tenant module keeps references inside one tenant and reads membership roles through a roles table.

  - `sql.modules.tenant.options.sameTenant` entries add a trigger that fails a write referencing another tenant's row with `TENANT_MISMATCH`, also through `match` and `through` columns.
  - `options.roleThrough: { table, id, column, where?, tenant? }` reads role names when memberships store role ids, taken from the provider's `roleSources` under the `provider` model. A `bs_role_scope` trigger refuses roles outside `where` on direct writes (`MEMBERSHIP_ROLE_SCOPE`), and doctor BS324 reports a shared roles table without `where`.
- `better-supabase/testing` checks Next.js navigations for instant renders and database budgets, and its kits check adapters and executors.

  - `expectInstant(page, options)` runs a navigation inside `@next/playwright`'s `instant()` (an optional peer) and checks what shows while the lock holds. `expectDbBudget(response, { maxCalls })` checks the `withDbStats()` header and waits `settleMs` for late responses.
  - `testAdapter`, `testExecutor` and `testPlugin` check custom adapters, executors and plugins against the first-party contracts.
- The usage block (`better-supabase/blocks/usage`) meters fractional quantities against quotas that follow the plan or billing cycle, and entitlements read from any plan catalog.

  - Quantities and limits are `numeric`, `recordMany` and `consumeMany` record several meters all or none, and a `null` limit is unlimited.
  - `options.meters` is a meter catalog in the config or a table, read by `usage.meters()`, `overview(organizationId)` and `current()`. `options.history` keeps each record, read by `history` and `breakdown`. Reading needs `usage.read` and recording `usage.record`.
  - The `billing` period follows `usage_billing_period(tenant)`, and `reportUsageToStripe({ overage: true })` sends only usage above the quota.
  - `entitlements.source` reads features from your plan tables or `"custom"`, with values through `entitlement_value`, and `entitlements.claim` sets the claim's shape (`EntitlementClaimOptions`).
- Vector search supports hybrid ranking, filters and scores. Run `better-supabase sql sync`.

  - `vectorSearch` entries take `type: "halfvec"`, `hybrid`, `boost`, `prefilter`, `predicate` and `order`.
  - `db.$search` takes `filter`, `text` and `score: true`; on a `hybrid` entry `text` alone ranks by full text when the embedding call fails.
  - `options.schema` sets pgvector's schema, which `sql sync` otherwise reads from your `create extension` statement.
- **Breaking:** `createInbox` in `better-supabase/blocks/jobs` is now `createWebhookInbox`, and its types are `WebhookInbox*`; the old names are removed. `better-supabase/blocks/inbox` has a different `createInbox` for the conversation inbox. Run `better-supabase sql upgrade`.

  - Messages record a tenant and dedupe per source and tenant, and `message.checkpoint(fields)` saves progress a retry resumes from.
  - `store(event)` stores an event an SDK already verified, and a source without secrets is store-only.
  - Sources take `maxAttempts`, `process` takes `budgetMs` and renews leases, and bodies over `maxBodyBytes` (1 MiB) get a 413.
- The `webhooks-in` module and `createIncomingWebhooks` in `better-supabase/blocks/webhooks` give each tenant trigger URLs with hashed tokens, and `createSafeFetch` calls URLs that users supply.

  - Endpoints verify Standard Webhooks, HMAC-SHA256 or a shared secret, with size and rate limits, keep secrets in Vault, and hand deliveries to the webhook inbox. `update`, `rotate` and `rotateSecret(id, { grace })` change them, and `options.subjects` attaches them to a record.
  - `verifyWebhook` and incoming endpoints accept Svix's `svix-*` headers.
  - `createSafeFetch(options)` allows public HTTPS URLs only, checks every redirect, drops credentials on a redirect to another origin, and throws `UnsafeUrlError` for a refused URL and `UrlCheckError` for a failed check such as DNS.
- The `workflows` and `workflow-builder` SQL modules record durable workflow runs and store graph workflows per tenant.

  - `better-supabase/blocks/workflows` records the runs of any engine in `workflow_runs` with cron schedules, semaphores and admission control, and `useWorkflowRuns` and `useWorkflowRun` in `/blocks/workflows/react` read them.
  - `better-supabase/workflow-sdk/world` is a Workflow SDK World on Supabase (Node only, `createWorld()`, the `workflow-sdk-world` module), and `better-supabase/workflow-sdk` adds `startFor`, `workflowStarter`, `startOnEvent`, `authorizeHook`, `hookMetadata` and `protectWebHandler`.
  - `better-supabase/blocks/workflow-builder` stores definitions, checked versions, triggers, credentials by `credential_ref`, a step library, node status and alerts, with `useWorkflowBuilder` and `useWorkflowCanvasRun`. `better-supabase/workflow-sdk/builder` adds `compileGraph`, `graphStarter` and `nodeRunReporter`. The new permissions are `workflow.edit` and `workflow.publish`.
  - Only the service role stores a version's compiled form (`createBuilder` writes it through `service`), and `graphStarter` compiles from the graph on every start. Node ids are 1 to 100 letters, digits, `_` or `-`.
  - The World refuses unsigned poll deliveries outside development and test, fails closed on a Vault read error, aborts a delivery after `deliveryTimeout` (300 s), and mirrors a run's tenant only when its actor holds `workflow.run` there.
- `verify_api_key` refuses a personal key while its user is banned in Supabase Auth (`banned_until` in the future) or soft-deleted. Before, only the configured disabled column stopped a personal key, so a banned user's key kept working after their sessions ended.
- The `data-lifecycle` module (version 5) exports and purges more module tables, leaves credentials and audit snapshots out of exports, and the organization purger revokes credential refs before the purge. Run `better-supabase sql sync` to get the new version.

  - Platform role assignments, outbox events, webhook secrets (purged, never exported), inbox tables, flag overrides and SCIM users per user, waitlist redemptions, AI provider keys, connector servers and grants, and workflow credentials join exports and purges.
  - Exports leave out every `credential_ref` column, and audit events lose `old_record`, `new_record` and the impersonation columns.
  - `createOrganizationPurger({ credentials })` revokes the `credential_ref` of each row the purge deletes through the `CredentialProvider` (connector grants for their user), only when the ref carries the organization. The rest come back in `purge.credentials.unrevoked` with a reason (`foreign`, `no_provider` or `not_revocable`), and a failed revoke stops the purge before it deletes anything.
  - The purger now checks that the deletion is due (`organization_credential_refs`) before it cancels billing or clears Storage.

## 0.5.1 (2026-10-04)

- Breaking (types): `SessionActor` is a union on `kind`: `oauth-client` (with `chain`), `support` (with `sessionId`, `readOnly` and `reason`) and `impersonation` (with `reason`), and `Impersonator` gains `kind`. An exhaustive `switch` on `session.actor.kind` needs the two new cases.

  Support sessions and impersonated sessions mark their `act` claim: `supportClaims` writes `act.kind: "support"` and `actingAs` writes `act.kind: "impersonation"`. `actorOf` reads them as their own actor kinds instead of OAuth clients, `session.impersonator` follows `actorOf`, so an OAuth client or agent chain is no longer shown as an impersonator, and `session.delegation` and the `scopes` guard apply to `oauth-client` actors only. An `act` with another `kind`, or a support level without `session_id`, makes the session invalid (`reason: 'actor'`). A support token minted by 0.5.0 (`session_id` without `kind`) still counts as a support session until 0.6. `supabaseClaimFixtures` from `better-supabase/testing` holds a support session (writable and read-only), an impersonated session, an OAuth client and an agent chain, each valid against PermDock's `supabase-claims-v1.json`.
- Breaking: `allow: ['anon']` no longer admits users from `signInAnonymously()`. Only `'anonymous'` admits anonymous sign-ins, and `'anon'` means a caller without a session. `['anonymous']` alone now admits anonymous sign-ins and refuses other users; before, it admitted nobody. A route that serves guests next to signed-in users lists `['user', 'anonymous']`, and a public route that also serves guests `['user', 'anonymous', 'anon']`. With PermDock, pair the default `allow` with `rls: { anonymousSignIns: 'deny' }` in `permdock.config.ts`.
- The entitlements module in PermDock mode reads `entitlement_members()` from the manifest's `rls.memberships` entries for its scope, the tables PermDock's `member_<scope>_ids_for` reads, and falls back to the hook's membership sources only for a manifest without `rls.memberships`. Doctor (BS408) warns when `rls.memberships` maps no table to the scope, and notes the fallback.
- The `permdock` access model reads PermDock's manifest itself. `better-supabase sql add` takes the helpers' schema from `rls.schema`, the scope from the root `rls.scopes` entry (the one without `within`) and the id type from that scope's `type`, whatever `entitlements.permdock` says, so a manifest with `rls.schema: "authz"` and a root scope `tenant` gets `authz.permitted_tenant_ids`. It stops instead of guessing when the manifest is missing, has no single root scope, or disagrees with `kits.access.permdock.scope`, `kits.access.permdock.schema` or `kits.access.idType`; 0.5.0 fell back to `permdock.permitted_organization_ids` and `uuid`. Code that renders the kit without the CLI (`renderKit`, `moduleBody`) now sets both `kits.access.permdock.schema` and `kits.access.permdock.scope`. Doctor reports the same problems, and helpers the manifest or the database lacks, as the new BS411 error.
- Under the `permdock` access model, `can_user()` and `member_can()` raise SQLSTATE `0A000` (hint `ACCESS_CALLER_ONLY`) for anyone but the caller instead of returning `null`, because PermDock's helpers read `auth.uid()`. The invitations module no longer re-checks the inviter's permission when an invitation is accepted, and the notifications module no longer filters recipients by their read permission, under that model; in 0.5.0 the re-check passed silently on the `null` answer, and the filter dropped every recipient but the sender. Check both in the app when they matter. Run `better-supabase sql add` to rewrite the installed files.
- The access kit docs, the `canAssign` JSDoc and the `can_assign()` SQL comment recommend PermDock's assignment rule for the `permdock` model: `canAssign: "permdock.permdock_can_assign({role}, {tenant}::text)"`, with the manifest's `rls.schema`. This is the assignment rule the 0.5.0 note "the `permdock` and `custom` access models need an assignment rule" refers to; see [the access kit](https://bettersupabase.com/docs/kits/access#permdock). Without it only the service role assigns roles, since PermDock projects don't install the `tenant` module, and doctor (BS411) warns.
- Under the `permdock` access model, `better-supabase sql add` and doctor (BS411) check every permission key the kit modules check against `permissions.catalog.json`, platform keys for `permdock_has` included. A key must be `rowConditions: false`, because PermDock's helpers check role and scope only; a key with row conditions, without the flag or missing from the catalog stops `sql add`. `kitPermissionKeys(kits, names)` from `better-supabase/sql` lists the keys with their module, action and scope, and `kitFilePaths(names, layout)` lists the files a set of modules writes without rendering them, so `sql list` works while the access settings are incomplete.
- `better-supabase gen` uses `@supabase/postgrest-typegen` 0.4.0. `database.types.ts` gains a `ComputedFields` key on every table and view: the names of its computed fields, or `never`. postgrest-js reads it to leave computed fields out of `select('*')`, and row-typed function arguments no longer include them. Run `better-supabase gen` to regenerate. Supabase CLI 2.119 doesn't write `ComputedFields` yet, so until it does, `supabase gen types` output differs from `gen` by that key.
- The optional `oxfmt` peer accepts any version from 0.66.0 below 1.0, so `pnpm add -D oxfmt` installs the latest. The runtime dependencies are ranges instead of exact versions: `@supabase/postgrest-js ^2.116.0` (the floor of the `@supabase/supabase-js` peer), `@supabase/ssr ^0.12.7`, `@supabase/server ^1.9.0`, `@supabase/middleware ^1.0.0` and `@standard-schema/spec ^1.1.0`, so an app shares one copy of each with its own Supabase packages. `@supabase/postgrest-typegen` stays an exact version.

  The `canAssign` JSDoc no longer says it defaults to true. The `custom` access model requires it. Without it, the `permdock` model lets only owners assign the owner role when the `tenant` module is installed, and lets only the service role assign roles when it isn't. The access kit docs now say the same, and their `custom` example sets `canAssign`, which that model requires.

## 0.5.0 (2026-10-04)

- Guards refuse anonymous users (`signInAnonymously()`, the `is_anonymous` claim) with a 403 `ANONYMOUS_USER` unless `allow` lists `'anonymous'` or `'anon'`, `toSession()` adds `anonymous`, and the `realtime-tables` kit module sends anonymous users no change signals. Before 1.0 this minor release is the breaking slot: routes that served guest sessions need `allow: ['user', 'anonymous']`.

  The framework adapters agree with each other. `ctx.apply(response)` adds refreshed session cookies and, after a write, `bs-primary-until`, so Hono, edge and the new oRPC `bs.fetchHandler(handler)` keep read-your-writes like Next.js does. MCP reads the session from the `Authorization` header only, answers an unreachable JWKS with a 503 instead of a scope challenge, sends a missing second factor as a plain 403, takes `advertisedScopes` (with `scopes` as a deprecated alias) and enforces `requiredScopes`. REST resources refuse cross-site form posts that ride on the session cookie (`CROSS_SITE_REQUEST`) and answer malformed keys and bodies with `invalid_input`, whose detail survives in production. Hono's `bs.onError` returns an `HTTPException`'s own response, Next.js route handlers turn unexpected throws into a 500 Problem Details response while `redirect()` and `notFound()` still work, and `contextForSession` requires the token's auth kind to match the session. `createServer` takes `fetch` for its PostgREST and supabase-js clients, the `auth` event carries `reason` and `rawSource`, the `react-server` build exports `hasEntitlement` and `useLiveCount`, and every adapter builds the user actor, impersonator included, from one function.
- The `audit` SQL kit module can adopt an existing audit table (`kits.audit.tables` and `columns`), and `audit()` takes `redact`, `category`, `event_prefix`, `target_type` and `tenant_column`. The new `audit_event` function records events that are not row changes, with an idempotency key. The options `appendOnly`, `readPolicy`, `impersonators`, `restricted`, `eventRoles`, `eventCategory` and `eventSource` add an append-only guard, a tenant read policy, hidden impersonation columns and a separate table for sensitive details. `purge_audit_log` honours an `audit_retention(tenant)` SQL hook, and `purgeAuditLog` from `better-supabase/jobs` takes a per-tenant retention callback. Run `better-supabase sql upgrade` to move from version 1.
- `better-supabase/hono` adds `bs.app()`, a `Hono` app typed with the adapter's `Env` and with `bs.onError` installed, and the type-only `bs.Env` for apps that build their own. After `@supabase/server`'s `withSupabase`, `bs.middleware()` reuses its verification of the bearer token when the stored claims are that token's payload, then runs its own claims, `act` and `userMetadata` checks.

  `clearOnUserChange(queryClient, auth)` in `better-supabase/query` removes the `["bs"]` queries when the signed-in user changes, for apps without React; `BetterSupabaseProvider` uses it.

  A bucket with `tenant` now checks paths on the client too: `upload`, `download`, signing, `remove`, `reserve` and `list` refuse a path in another tenant's segment, or any path when the connection has no tenant, with a `forbidden` error before calling Storage. Pass `{ context }` or `{ tenant }` to `connect()`, or `{ allTenants: true }` for cross-tenant admin work; `deleteAccount` does the latter. `client.path(target)` returns the checked path.

  Jobs record the enqueuing request's actor and tenant: `enqueue(queue, payload, { context })` and `schedule(..., { context })` store them next to the payload, and the handler gets them as `job.context`, ready for `db.$with(job.context)`. A job without a tenant gets the `tenant()` plugin's `onMissing` unless the worker runs with `allTenants: true`.

  `actor()` fills an `impersonatedBy` column (generated from `impersonated_by`, the column the SQL kit's `track_actor` stamps) from the impersonating admin, and clears it on writes without one.

  Event sink sends are tracked on `betterSupabase.events` (`pending`, `settled()`). Next.js routes and actions hand them to `after()`, and edge handlers to `waitUntil`: the Workers `ctx`, or `createEdge(..., { waitUntil })` on Supabase.

  The PermDock guide has oRPC and Hono recipes that refuse a procedure or route without a permission.
- Jobs run without pgmq or pg_cron when you want. `kits.jobs.options.backend: "table"` stores jobs in `better_supabase.job_messages` and claims them with `for update skip locked`, and `kits.jobs.options.scheduler: "drain"` stores schedules with a time zone each. `jobs.drainRoute({ secret, handlers })` is a route for Vercel Cron that enqueues due schedules and drains queues within a time budget, and `drain` takes a `budgetMs`. `schedule` takes `{ timeZone }` and validates the cron expression first. `createJobs` accepts any `QueueBackend` (API version 1), with `sqlQueueBackend`, `pgmqPublicBackend` and the `testQueueBackend` conformance kit. The `jobs` module is now version 2: `better-supabase sql upgrade` drops the old four-argument `schedule_job`.
- The SQL kit's rows and role settings, which a schema diff can't capture, move to `supabase/better-supabase-data`, and the new `better-supabase sql data` writes them into a migration stamped after the newest one. `rate-limit` sets `pgrst.db_pre_request` that way, and doctor BS313 warns when the live database never calls `check_request()`. `sql upgrade` writes next to the located `config.toml`, and each module rejects options it doesn't declare.

  Breaking: `entitlements` no longer defaults `entitlements.customer` to `organizations.stripe_customer_id`. It reads the managed `organizations` module's column when that module is installed; otherwise `sql add` stops until you set it. `tenant_ids_with_entitlement(key)` gives policies a set check.

  Jobs enforce max attempts at claim, retry with full jitter and replay dead letters (`replay_dead_job`, `jobs.replay`). The outbox orders by `(xid, position)` and gives events uuid ids. Outgoing webhooks take a lease token, follow the Svix retry schedule with `Retry-After`, and disable a destination after failing for `disableAfter`. Notifications back off between deliveries and fail them after `max_attempts`. Key indexes lead with the key, webhook policies read `tenant_ids_with()` once per statement, `jsonb-schemas` adds its checks `not valid` and validates them separately, and `purge_rate_limits()`, `purge_webhook_deliveries()` and `purge_notifications()` join the other purges.
- Kits share one set of extension points: typed events, policy callbacks, SQL hooks and fixed attribute names.

  - `betterSupabase.on("kit", handler)` receives `support.*`, `org.*`, `invitation.*`, `notification.*` and `webhook.*` events with a copy of their data. `onKitEvent(betterSupabase, "support.*", handler)` from `better-supabase/events` filters by type or prefix and types the data.
  - `forwardKitEvents()` and `kitCloudEvent()` send kit events to an `EventSink` as CloudEvents, and `traceKitEvents()` from `better-supabase/otel` records them with the `KIT_ATTRIBUTES` names (`better_supabase.org.id`, `better_supabase.support.session_id`, ...).
  - Policy callbacks (`Policy`, `PolicyDecision`) fail closed: only `true` allows, and a throw or rejection denies.
  - `kits.<module>.hooks` sets where a module looks for the app's `before_*` and `after_*` SQL functions, and `kits.<module>.events: false` stops it writing its events to the outbox.
- Breaking: the SQL kit fails closed. `current_tenant_id()` returns a tenant only while the caller is a member, the claim is cleared when a member is removed, and `kits.access.activeTenant` defaults to `'resolver'` (the tenant `ServerOptions.tenant` resolved, then the claim). Disabled organizations deny access, the `permdock` and `custom` access models need an assignment rule, and only an owner can transfer ownership. A member can never raise their own role or assign one above it.

  Platform invitations move to `platform_invitations` under a role ceiling that accept checks again, accept checks that the inviter can still assign the role, and `valid_for` is capped by `maxValidFor`. Support sessions refuse platform targets and writes by default and allow one active session per admin; a token with an `act` claim has no platform permissions.

  Doctor BS312 reports a kit schema listed in `[api] schemas`. `set_actor` keeps `created_by` on updates, `track_realtime` refuses a table without the tenant column, the rate limit and `request_ip()` use the right-most forwarded hop, audit is append-only by default, idempotency keys are scoped to the caller, public buckets get no select policy, members see only public profile columns, and outgoing webhooks follow no redirects, cap the response body and use 32-byte secrets.
- Breaking: the SQL kit follows one naming standard. Run `better-supabase sql upgrade`, then `sql sync` and `sql data`; the [0.4 to 0.5 guide](https://bettersupabase.com/docs/migration/0.4-to-0.5) lists every step. The forward steps rename `memberships.org_id` and `invitations.org_id` to `organization_id`, `better_supabase.audit_log` to `audit_events` (with `occurred_at` and `organization_id`, and a read-only `audit_log` view until 0.6), and `audit_trigger()` to `audit_row_change()`. Doctor reports the old column names in your SQL (BS309), also when a column is unqualified next to its table.

  The modules new in this release use the same names: `webhook_endpoints` with `event_types` and the statuses `pending`, `delivering`, `succeeded`, `retrying`, `dead` and `canceled`; notifications with `type`, `data`, `actor_id` and `user_id`, and `types` instead of `kinds` in `createNotifications`. Permission keys follow `<area>.<verb>`, and managed tables get `updated_at` triggers and indexes on their foreign keys.

  Breaking: `toCloudEvents` and `kitCloudEvent` put the actor in `data.actorId` instead of the `actorid` context attribute, so user ids stay out of broker headers. The outbox relay prefixes event types with `dev.better-supabase`, and `webhooks.sink()` removes the prefix again.
- The new `sessions` SQL module adds `better_supabase.session_active()` for restrictive policies: it is false once the token's session was revoked or expired, or the user is banned or deleted.

  Options that only exist to match an existing schema are accepted in `mode: "adopt"` only: `tokenStorage: "plain"` for invitations, `secretStorage: "column"` and non-`text` `eventIdType` or `runIdType` for webhooks-out, and `kitSource` or `defaultSource` for the outbox. Doctor BS314 warns about each until you remove it. `better-supabase/sql` exports `migrationOptionUses(kits)` to list them. The `assignmentCeiling` and `triggerPrefix` options, the invitations `errorCodes` option and `kits.access.disabled.tenantKey` are removed.
- SQL kit modules now fit existing schemas. `kits.<module>` in the config sets a module's mode (`managed`, `adopt` over your own tables, or `custom` where you write the contract functions), its schema, table and column names, tenant id type and permission keys. Each file's header records the module version and mode, and schema files record them in `better_supabase.kit_modules`. Doctor BS307 checks the functions of custom-mode modules, and BS304 points hand edits at `kits` instead.

  The new `access` module gives policies and kit modules one permission check, `can(scope, id, permission)`, with `tenant_ids_with()`, `is_platform()`, `can_user()`, `can_assign()` and `permission_claims()`. `kits.access.model` picks a role list from the config, role and permission tables with per-tenant overrides, PermDock or your own functions, and `kits.access.disabled` switches off tenants and users with a `disabled_at` column. The `tenant` module (version 2) takes its role names from `kits.access.roles`, adds `memberships.last_used_at` and `org_member_role()`, writes the memberships claim as an array or a map (`options.claimFormat`), and reads the active tenant from `kits.access.activeTenant`: a resolver (the default), the claim or a profile column.

  For resolvers, `createServer` takes `tenant: (request, auth) => id`, and `context()` takes `{ tenant }`. The tenant becomes `context.tenant`, the `better_supabase.tenant` setting over Postgres and the `x-bs-tenant` header (`TENANT_HEADER`) over the Data API. `postgres.asUser`, `executorFor` and `transaction` take `settings` and `readOnly`. Doctor BS308, with `--as <user id>`, warns when the access token hook writes no tenant claim while the claim is the active tenant.

  `better-supabase/config` exports the kit config types (`KitsConfig`, `KitModuleConfig`, `KitMode`, `AccessKitConfig` and `ActiveTenantSource`) for apps that build their `kits` config in a separate module.
- SQL kit modules have versions and an upgrade path, and a codemod rewrites renamed APIs.

  - `better-supabase sql upgrade` reads each module's `@bs-kit` version (a file without one is version 1), writes the forward steps into `supabase/migrations/<timestamp>_better_supabase_kit_upgrade.sql` and rewrites the module files. `--check` exits 1 when a module is behind or a file is stale.
  - Deprecated kit functions keep a wrapper under the old name until they are removed. `upgradePlan()`, `kitDeprecations()` and `moduleVersion()` are exported from `better-supabase/sql`.
  - `track_updated_at()` and `audit()` warn about an existing trigger that does the same work, and drop it with `replace_trigger => true`.
  - Doctor reports deprecated or removed kit symbols in schema files and policies (BS309), a kit trigger next to an equivalent one (BS310), and a module behind its version on disk or in `better_supabase.kit_modules` (BS311). BS304 skips files BS311 reports.
  - `better-supabase codemod <version>` rewrites imports, members, JSX props and call options for renamed APIs (`0.4`, and `0.5` for `createMcp`'s `scopes`), skipping strings and comments, and lists the lines it leaves for review. `--dry-run` prints the diff.
- Add the `notifications` SQL kit module and `better-supabase/notifications`. `notify(jsonb)` is a `security definer` sender that checks `notifications.send`, leaves out the actor and non-members, and applies subject subscriptions and per-channel preferences. `createNotifications` sends with typed data and reads, counts, marks, dismisses and resolves notifications; `deliver()` sends email, push and other channels through `NotificationChannel` implementations with leases and retries. `useNotifications` from `better-supabase/react` keeps a list current over a private Realtime topic. Existing tables work with `mode: 'adopt'`, and the topic and event names are configurable. `OrgsTransport` is now `KitTransport`, exported from both `better-supabase/orgs` and `better-supabase/notifications`.
- Organizations and invitations. The new `organizations` SQL kit module creates, updates and deletes organizations (hard or soft), changes member roles, removes members, transfers ownership and switches the active organization through `kits.access.activeTenant`. A deferred trigger keeps an owner in every organization, and a trigger stops members from raising their own role or assigning one above it. The `invitations` module moves to version 2: `invite_member` returns the invitation with its token, invitations can be resent, revoked, declined and previewed without a session, can carry `prefill` data and can target the platform under the catalog access model, and accepting re-checks that the inviter may still invite. `create_invitation` keeps its 0.4 signature. Both modules check permissions through the access contract, so `invitations` now needs `access`, and both support `mode: 'adopt'` with options for token storage, slug rules, error SQLSTATEs and extra columns. The new `better-supabase/orgs` subpath calls them with `createOrgs`, over Postgres (`sqlTransport`) or the Data API (`rpcTransport`), with `canInvite` and `onInvite` callbacks and `org.*` and `invitation.*` kit events, including the new `org.updated` and `org.deleted`. The `tenant` module now installs on a fresh database under `kits.access.model: 'catalog'`.
- Transactional outbox. The new `outbox` SQL kit module stores events with `emit_event(type, payload, subject, tenant, key, source)` in the writing transaction, deduplicates by key per tenant, adds `track_events(table)` row triggers and keeps events for `outbox_history` until `purge_outbox`. Named consumers read in order with their own cursor and a lease, and a claim never skips an event whose transaction is still open. The `organizations` and `support-sessions` modules write their events to it once it's installed. `createOutbox` in `better-supabase/jobs` emits, registers consumers, relays events as CloudEvents to any `EventSink` and serves `relayRoute` for a cron caller. The module supports `mode: 'adopt'` for an existing events table.

  The `defaultSource` option fills the source of `emit_event` calls that pass none, and `kitSource` sets the source kit modules write (`better-supabase/{module}` by default), so an adopted events table with a check on its source column keeps working. Adopt mode still creates the consumers table, since an existing app has no cursors yet.
- The PermDock integration fails closed in more places. Buckets and topics in `permdock` mode now call PermDock's helpers in `permdock`, PermDock's default `rls.schema`, instead of `public`; set `schema: 'public'` on the policy if your PermDock config writes them there. `gen` and doctor BS214 refuse PermDock bucket policies when `permissions.catalog.json` is missing, and the catalog must be version 1. `sql add entitlements` refuses a PermDock project without a manifest or `rls` block instead of falling back to the tenant module (set `entitlements.permdock: false` for that). BS214 also reports a helper schema other than the manifest's, a scope the manifest doesn't declare and a key checked at another scope than its catalog entry. BS408 checks that PermDock's hook fills `claims.features` from `better_supabase.feature_claims` and that a membership source covers the scope. The new BS409 reports a `claims.tenant` that differs from the manifest's `rls.tenantClaim`, PermDock markers other than v1 and a `claims.scope` that isn't the root scope. Scope id types `integer`, `int8` and other aliases are accepted, and MCP table tools take a permission per operation from the resource's `meta`.
- Plugins compose without holes. `timestamps()`, `actor()` and `softDelete()` refuse caller-supplied values for the columns they fill unless the call passes `{ override: true }`, and generated JSON Schema and OpenAPI documents mark those columns `readOnly`. On tenant tables, an upsert that updates on conflict needs the tenant column in its conflict target, the SQL executor guards the update with `where <tenant> = excluded.<tenant>`, a query whose includes reach a tenant table fails closed without a tenant, and numeric tenant columns compare by their text. An upsert that updates a soft-deleted row restores it.

  `rules()` runs before every other plugin. `noUnboundedFindMany` skips aggregates, `maxLimit` ignores `paginate()`'s look-ahead row, `requireTenantContext` reads the same claim paths as `tenant()`, and `noSensitiveSelect` checks reads only, because writes without a `select` no longer return sensitive columns. Offset `paginate()` orders by the primary key by default. `validation()` decodes codec columns (Temporal values, `bigint`) before validating and encodes them afterwards.

  Mutation events give hooks and listeners a copy of the rows, so they can't change the result (`testPlugin` checks this), and carry `intent` (`softDelete` for a delete that became an update), the affected primary `keys` when they are known, and the `tenant` that `tenant()` resolved. CloudEvents and cache invalidation use them, so soft deletes send `row.softdeleted` events and invalidate their rows. `defineReadSet` warns when query plugins scope tables its generated function reads. The audit kit keys entries by each table's primary key and reads the tenant column from `plugins.tenant.column`, and `gen` refuses a soft-delete column that isn't a timestamp.
- Profiles and image buckets. The new `profiles` SQL kit module creates a profile on sign-up from auth metadata (full, first and last name, avatar), allocates a unique username, mirrors `auth.users.email`, grants updates only on the columns users own and refuses changes to service-owned columns (`PROFILE_COLUMN_READONLY`). It supports `mode: 'adopt'` for an existing table keyed by any column, an `after_profile_sync` hook, extra columns, a read policy for people in the same organizations and `backfill_profiles()`. `better-supabase/storage` adds `avatarBucket()` and `orgLogoBucket()` presets and a bucket policy, `{ access: { read, write } }`, that checks permissions through the SQL kit's access contract.
- Support mode: platform admins can view the app as a user. The new `support-sessions` SQL kit module records sessions in a table (or an adopted one), checks `is_platform('support.start')`, writes `support.started` and `support.ended` to the audit log and can call your access token hook for the target's claims. `createServer` takes `support: supportSessions({ store, authorize, claims, policy, cookie })`, which apps without support mode never bundle; while the `bs-support` cookie names a running session, contexts, sessions, actions and routes run as the target over Postgres, read-only by default, with an `act` claim that carries the session id. Next.js gets `bs.startSupport()`, `bs.stopSupport()` and `supportTag()`, React gets `useSupportSession()`, and `better-supabase/testing` gets `testSupportSessionStore`. The audit module records the session in a new `support_session_id` column; an adopted table maps `supportSession` to `null` when it has none.
- Values from Postgres and the peer libraries no longer break responses. JSON responses from the server adapters and MCP write `bigint` values as decimal strings. A `timestamptz` or `timestamp` holding `infinity` comes back as an `invalid_value` error (status 500, with `column`) instead of throwing, because Temporal has no infinite value. Temporal values from another realm or a second polyfill copy are recognized by their `Symbol.toStringTag`, and Standard Schema issues with symbol path keys keep the error serializable.

  `loadEnv()` reads inline keys from `SUPABASE_JWKS`, as `@supabase/server` does, and verifies with them without fetching `jwksUrl`. The OpenTelemetry plugin writes `db.namespace` as `{database}|{schema}` (`postgres|public` by default, `otel({ database })` to change it), adds `server.address` and `server.port` from `otel({ server })` to spans and metrics, and sets `db.response.status_code` only for SQLSTATE codes. `BetterQueryMeta` builds on the app's `Register['queryMeta']`, and `send_email`'s `email_data` accepts fields Auth adds later.

  Doctor's BS410 reports HTTP auth hooks and checks their `v1,whsec_` secrets, and its custom access token hook event carries `iss` and `amr`. The peer ranges now state what the code needs: `pg >=8.15 <9`, `@tanstack/query-core ^5.62.0`, `@orpc/server >=2.0.0-beta.40 <3`, `hono <5`, `next <17`, `@opentelemetry/api <2`, and `oxfmt 0.66.0`, the version `@supabase/postgrest-typegen` pins; the `gen` notice and docs show how to allow a newer oxfmt.
- Add the `webhooks-out` SQL kit module and outgoing webhooks in `better-supabase/webhooks`. Destinations subscribe to event types (exact, `*` or `prefix.*`), secrets live in Supabase Vault (or a column) and rotate with an overlap, and every delivery is logged with its status, response and duration. `createWebhooks` publishes events idempotently, dispatches to one destination, and `deliver()` or `deliverRoute()` sends due deliveries with leases, retries with backoff, dead letters, redelivery and auto-disable after repeated dead letters. Requests are signed with Standard Webhooks by default or with `hmacSigner` for an existing format, and `publicUrl()` rejects private and local addresses, also on each redirect. `WebhookSigner`, `WebhookTransport` and `WebhookSecretStore` are versioned extension interfaces with conformance kits in `better-supabase/testing`. RLS policies in the `notifications` module now use `better_supabase.can`, which clients may execute, instead of `member_can`.
- The docs and skills follow the Naming page's file layout everywhere. The PermDock page defines `betterSupabase` in `src/lib/supabase/index.ts` and creates `bs` in `server.ts` and `client.ts`, and every Next.js `server.ts` starts with `import "server-only"`. The docs drift check now fails a code block that breaks the layout.
- Doctor BS404 and `doctor --fix-grants` follow pg-delta for PermDock's hook. With `[experimental.pgdelta] enabled = true`, they point to `permdock supabase hook generate --out <schema file>` without `--grants-out`, then `supabase db schema declarative sync`, instead of a grants migration. A hook whose grants are in the declarative schema file that defines it now counts as granted under pg-delta, and the finding for a file that already grants the hook names `supabase db schema declarative sync` before `supabase migration up`.
- Doctor BS408 checks exactly the PermDock helpers the `entitlements` module calls for the chosen scope, and no longer claims PermDock writes `member_<scope>_ids_for` for every scope. It warns when the manifest lacks `member_<scope>_ids` or doesn't let `authenticated` execute it, when it lacks `member_<scope>_ids_for` (add a membership source for the scope in `permdock.config.ts`), and when `supabase_auth_admin` may not execute `member_<scope>_ids_for` (add `supabase.hook.claims: { features: 'better_supabase.feature_claims' }`).
- The PermDock MCP recipe in the docs and the auth skill fails closed: a tool without a PermDock permission in `meta` is hidden (`visible` returns `false`) and refused (`authorize` returns `{ allowed: false }`). The page also shows PermDock's `decide` for putting the denial reason in the refusal.
- The `entitlements` kit module takes its PermDock scope from the manifest. Without `entitlements.permdock.scope`, it now uses the manifest's root scope (the `rls.scopes` entry without `within`) instead of `organization`, so a PermDock project whose root scope is `tenant` works without config. A manifest with no root scope or several stops `sql add entitlements` and doctor BS408 asks for `entitlements.permdock: { scope }`. An explicit `scope` still overrides, `false` still opts out, and a scope the manifest doesn't list is still reported by BS408. `permdockKeyStatus` and the `PermdockCatalog` and `PermdockKeyStatus` types are exported from `better-supabase/sql`.
- In PermDock mode, the `entitlements` kit module renders the tenant argument of `has_entitlement`, `tenant_entitlements` and `tenant_stripe_customer`, and the rows of `stripe_customer_tenants`, with the scope's id type from the manifest's `rls.scopes` (`uuid`, `text` or `bigint`) instead of always `uuid`. A missing or other type stops `sql add entitlements` and doctor BS408 reports it. `better-supabase/sql` exports `KIT_ID_TYPES`, `isKitIdType` and the `KitIdType` type, and `KitPermdock` has a required `idType`.
- The auth skill's PermDock caching recipe works as written. It passes only static tags to `bs.cached()`, then calls `cacheTag(snapshotTag(session.user.id))` and `cacheLife(cacheLifeFor(snapshot))` inside the loader once the snapshot is built, because the user id and the snapshot don't exist before `bs.cached()` returns. It pairs the recipe with `bs.invalidateSession(userId, { tags: [snapshotTag(userId)] })`.
- PermDock's catalog is read fail closed. `defineBucket` and `defineTopic` with `catalog` accept only keys marked `rowConditions: false`: a key whose entry has no boolean `rowConditions`, or that the catalog doesn't list, now throws with a message to regenerate the catalog with a current `permdock catalog`. Doctor BS214 reports those keys as errors, and `better-supabase gen` refuses to write their bucket policies.

## 0.4.0 (2026-10-03)

- The CLI ships inside `better-supabase` again. Installing `better-supabase` gives you the `better-supabase` command, so drop `@better-supabase/cli` from your dev dependencies (it was never published) and run `npx better-supabase init` in a new project. The commands and their options are unchanged. The CLI's own dependencies are bundled into the package, so apps install nothing extra; `pg` stays an optional peer that the CLI needs to read your database.

  Import `run`, `registerCommand`, `defineCliCommand` and the introspection helpers from `better-supabase/cli`. `@supabase/config` is an optional peer again, for reading `supabase/config.toml`.

  `VERSION`, `better-supabase --version`, doctor reports and the header of newly written SQL kit files now show the package version instead of `0.0.0`. Existing kit files are not reported as changed, because the comparison ignores that version.
- Names are now the same in every adapter. The definition from `defineSupabase` is `betterSupabase`, and every runtime instance an adapter creates is `bs`. They live in `lib/supabase/index.ts`, `lib/supabase/server.ts` (with `import "server-only"` in Next.js) and `lib/supabase/client.ts`, which is what `better-supabase init` now writes. The old names have no aliases; the compiler points out each one. [Naming](https://bettersupabase.com/docs/concepts/naming) lists the conventions.

  | Before                                                                | After                                                                                         |
  | --------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
  | `createBrowser`, `BetterBrowser`, `BrowserOptions`, `BrowserAuth`     | `createClient`, `BetterClient`, `ClientOptions`, `ClientAuth`                                 |
  | `<BetterSupabaseProvider browser={browser}>`, `BrowserLike`           | `<BetterSupabaseProvider client={bs}>`, `ClientLike`                                          |
  | `client.sb` and the `sb` option of `testExecutor` and the test plugin | `betterSupabase`                                                                              |
  | `next.server()`                                                       | `bs.context()` (pass a `Request` to read it instead of the incoming one)                      |
  | `next.serverFor(session, { token })`                                  | `bs.contextForSession(session, { token })`                                                    |
  | `BetterEnv` and `bs.handle()` (Hono)                                  | `HonoEnv` and `bs.handler()`                                                                  |
  | `bs.toORPCError()`                                                    | `bs.toOrpcError()`                                                                            |
  | `HandlerOptions` (Edge)                                               | `MiddlewareOptions`, shared by Hono, oRPC and Edge and exported from `better-supabase/server` |
  | `handler` (MCP)                                                       | `endpoint`                                                                                    |
  | `Queries`, `CreateQueriesOptions`, `queries.key`                      | `BetterQueries`, `QueriesOptions`, `queries.$key`                                             |
  | `Postgres`                                                            | `BetterPostgres`                                                                              |
  | `DefineSupabaseOptions`                                               | `SupabaseOptions`                                                                             |
  | `repository.$table`                                                   | `repository.$tableName`                                                                       |

  `createHono`, `createOrpc`, `createEdge` and `createMcp` now keep the claims and profile types from `.claims()` and `.userMetadata()`, so `c.var.auth`, `context.auth`, the edge handler's `auth` and MCP's `ctx.auth` are typed by your schema. `better-supabase/next` also exports the `LiveCountSeed` type that `bs.liveCount()` returns.
- Less work per request in auth and the adapters.

  - The Next.js adapter verifies the token once per render scope: `context()`,
    `session()` and `cached()` share one resolution. `BetterServer` gains
    `contextFromResolution(resolution, request)` for the same pattern elsewhere.
  - A token seen before skips the claims and `userMetadata` schemas as well as
    the signature check, per schema pair.
  - `createServer` fetches the JWKS when it is created, so the first request
    doesn't wait for it. Pass `prefetchJwks: false` to turn it off; it is off
    under `NODE_ENV=test`.
  - Bearer requests parse cookies only when something reads them, and contexts
    read the replica pin cookie only when a read URL is configured.
  - Job workers back off from `pollInterval` to `maxPollInterval` (30 seconds by
    default) while the queue is empty, and keep the leases of every job in a
    claimed batch alive, not only the running one.
  - Webhook verification imports each secret's key once, compares signatures
    with `crypto.subtle.verify`, and checks the headers before reading the body.
  - The MCP server builds its tool list once when no `visible` hook is set.
  - The OpenTelemetry plugin builds span and metric attributes once per table
    and operation.
  - Edge resource routes answer unknown paths before resolving auth, and a
    malformed id is a 400 instead of a 500. CORS header values are built once.
- A faster CLI that reads the database less often.

  - `--help` and each command's `--help` start in about 30 to 50 ms instead of
    130 to 150 ms: the commands, config loading, env validation, prompts and
    the typegen schemas load only when a command runs.
  - `gen` hashes the system catalogs with one query and reuses the snapshot
    cached in `node_modules/.cache/better-supabase` while the schema is
    unchanged. `gen --watch` keeps one connection open and polls that hash, so
    an unchanged schema costs one small query per interval.
  - Introspection runs its queries concurrently over a pool of four
    connections. Connecting gives up after 10 seconds and each introspection
    query after 2 minutes; Ctrl-C ends the connection or Management API request
    and exits with code 130.
  - `doctor` reads the snapshot and runs its live checks and splinter over one
    connection, and reads its input files concurrently.
  - `oxfmt` is now an optional peer. Without it, `gen` writes
    `database.types.ts` unformatted and prints a notice instead of failing.
  - Generated files and doctor reports sort names by code point, so they no
    longer depend on the machine's locale. Run `better-supabase gen` once; the
    order of a few entries in `generated.ts` and the validator files can change.
  - Breaking: `parseSnapshot` from `better-supabase/cli` now returns a promise,
    so the typegen schemas load on first use. Add `await`. `loadSnapshot` takes
    `signal` and `cache` in its source options.
- Fixes four bugs the performance audit found, one of which changes behavior.

  - `findMany` without `orderBy` now orders by the primary key's database names. On a camel-cased table whose key isn't `id` (`customerTags` with `customerId` and `tagId`) it sent `order=customerId.asc`, which PostgREST rejects.
  - `topic.send()` no longer closes a subscription on the same topic. realtime-js reuses the open channel for a topic, and `send()` removed it after sending.
  - `liveQuery` keeps the shared channel when a listener re-joins in the same tick (React StrictMode remounts), instead of subscribing the new listener to a closing channel.
  - A session refresh now times out after `refreshTimeoutMs` (5000 by default, an option of `resolveAuth` and every adapter's `auth`) and counts as a network failure. Before, a hung Auth request blocked every later request carrying the same refresh token. A rejected refresh is reused for ten seconds, like a successful one.

  Breaking: where refreshing is off (Server Components, route handlers, prefetches, MCP), a token in its last 60 seconds is now valid until its `exp`. It used to resolve as `{ kind: 'anon', reason: 'expired' }`, so pages rendered signed out in the last minute of every token. `leeway` now only decides when the proxy refreshes.
- Generated files and types that cost less to check and to bundle.

  - Breaking: `gen` writes the schema metadata to `generated.meta.js` with a
    `generated.meta.d.ts` next to the main module, which imports it. TypeScript
    reads the metadata as `SchemaMeta` instead of checking a large object
    literal, which cuts check time and editor memory on large schemas. Run
    `better-supabase gen` and commit both new files.
  - Breaking: `BetterPostgres` gains `executorFor(claims)`, and `createServer`
    uses it for `ctx.sql` and `actingAs()`. Apps that don't pass `postgres`
    no longer bundle the SQL compiler; the Next.js, Hono, oRPC, edge and MCP
    entries are about 5 KB gzip smaller. A custom `BetterPostgres` implements
    `executorFor` as `postgresExecutor(asUser(claims))`.
  - Reads without `select` or `include` return the row type directly, which
    removes about a quarter of the type instantiations a query costs.
  - The build marks library modules as side-effect free and annotates
    module-level objects as pure, so bundlers drop the parts an app doesn't use.
- Faster request path in the core runtime.

  - `connect()` costs the same for any number of tables: every connection shares
    one prototype of table getters, and repositories are built on first access.
  - For a signed-in user, `ctx.db` (and `dbFor()`) on the server runs on a bare
    PostgREST client, so requests that only query data no longer build the
    Realtime, Storage and Auth clients. `ctx.supabase` and `ctx.db.$client`
    still return the full supabase-js client, built when first read.
    `better-supabase` now depends on `@supabase/postgrest-js` at the version
    supabase-js uses.
  - Default selections, rendered select strings, column lookups, unique keys,
    invalidation targets and the tables a query spec reads are computed once per
    table or spec instead of on every call. Plugin hooks, tenant resolution and
    claim paths are resolved once, and `mutation` and `error` payloads are only
    built when someone listens.
  - Row decoding and paging copy each row once instead of spreading and deleting
    keys in loops.
  - Bucket connections take `{ cacheSignedUrls: true }` to reuse a signed URL
    until shortly before it expires. The cache belongs to the connection.
  - Outside production, the event hub warns once when an event collects more
    than 50 handlers, which usually means a missing unsubscribe.

  `invalidationTargets()` now returns a frozen `readonly string[]`.
- The Agent Skills cover 0.3. A new `better-supabase-auth` skill teaches sessions, typed claims, OAuth clients and agents behind a token (`session.actor`, `session.delegation` and the `scopes` guard option), `checkSession` before irreversible actions, what happens when claims change, and how to run next to PermDock. The `better-supabase` skill adds an upgrade workflow, cursor pagination, `Temporal` values, the CLI's `--json`, `--db-url-stdin` and exit codes, and `member_org_ids()` in tenant policies. The `better-supabase-api` skill adds `scopes`, cursor resources, the MCP `authorize`, `visible` and `allowedHosts` options, the kit's purge functions and the Postgres pool options. The `better-supabase-testing` skill adds delegated-token API tests, `Temporal` in tests and doctor in CI. Run `better-supabase skills install` to update installed skills.

## 0.3.0 (2026-10-02)

- Name the OAuth client or agent behind a bearer token. A user session now carries `actor` and `delegation`, read from `client_id`, `scope` and the RFC 8693 `act` chain the way PermDock's `actorOf` and `delegationOf` read them. A malformed `act` chain resolves to `{ kind: 'invalid', reason: 'actor' }` and a 401, so `InvalidReason` gains `'actor'`: an exhaustive `switch` over it needs the new case. The `scopes` guard option on `next.route`, `next.action` and the edge, Hono and oRPC adapters answers 403 with an RFC 6750 `insufficient_scope` challenge when a delegated token lacks a scope; the user's own token is not limited. `forbidden` errors and Problem Details carry the needed `scopes`. `better-supabase/server` now exports `toSession`, `AuthSession`, `ActClaim`, `SessionActor` and `SessionDelegation`. A new monorepo guide shows one runtime package that owns `defineSupabase`, with domain packages typed from its `db`.
- Breaking: the `BetterResultShape` type is now `BetterResultValue`. It is still the type `toBetterResult` returns, with the `status`, `value` and `error` fields of a better-result value; rename the import to upgrade.
- On the Postgres executor, `createMany` and `upsertMany` split an insert that needs more than 65,535 bind parameters into several statements and run them in one transaction, instead of failing. `upsertMany` sends rows sorted by the conflict columns, so concurrent upserts over overlapping rows lock them in the same order instead of deadlocking; its returned rows follow that order.
- `checkSession(sql, auth)` from `better-supabase/auth` and `better-supabase/server` confirms that a user token's session still exists in `auth.sessions`, and returns an `unauthorized` error with code `SESSION_REVOKED` when the user signed out or the session was ended. Call it before actions you can't undo, such as deleting the account. Nothing calls it by default, so other requests still verify tokens without a round trip.
- The CLI runs on citty. `init` and `add` ask for the casing, the integrations and whether to overwrite files when they run in a terminal; `--yes`, CI and piped input skip the questions. Output is colored in a terminal (`NO_COLOR` turns it off), database work shows a spinner on stderr, and `gen --check`, `introspect --check` and `sql sync --check` print a unified diff of each stale file.

  `registerCommand` takes a command from the new `defineCliCommand`, and `list()` splits list options. The 0.2 form, `registerCommand(name, command, help)`, still works and is deprecated. `help()` replaces the `HELP` constant.
- Breaking: the CLI follows one set of conventions for output, errors, prompts and secrets.

  - `--db-url` is removed from `gen`, `introspect`, `doctor` and `seed`, because a connection string holds the password and arguments end up in shell history and the process list. Set `$DATABASE_URL` or `source.dbUrl`, or pipe the URL in with `--db-url-stdin`.
  - `--json` is a global option. It prints one JSON document on stdout: the command's result, or RFC 9457 Problem Details with a `code` when it fails. `doctor --format json` becomes `doctor --json`.
  - `--yes` (`-y`) is a global option. Prompts never run under `--json`, `--yes` or `CI`.
  - Exit codes are 0 for success, 1 for a failure and 2 for a usage, config or environment error. Every error code has a section on [the errors page](https://bettersupabase.com/docs/cli/errors).
  - A mistyped command gets a suggestion: `Did you mean "gen"?`.
  - `better-supabase.config.*` loads through c12 and is checked against a schema; an unknown key or a wrong value stops the run with each problem's path. `DATABASE_URL` and `SUPABASE_API_URL` must be URLs.
  - `run()` no longer reads `process.env`: pass `run(argv, { env: process.env })`. `CliIo.env` and `CliIo.now` are removed, and `CliIo.stdin` is new.
  - New exports: `CliError`, `CLI_ERRORS_URL`, `commandNames`, and the `CliEnv`, `CliProblem` and `CliErrorCode` types. A command can throw `CliError` and return `data` for `--json`.
- The CLI moved to its own package, `@better-supabase/cli`, released at the same version as `better-supabase`. Install it with `pnpm add -D @better-supabase/cli`; the `better-supabase` command and its options are unchanged.

  Breaking for `better-supabase`: the package no longer ships the `better-supabase` bin or the `better-supabase/cli` subpath. Import `run`, `registerCommand` and the introspection helpers from `@better-supabase/cli` instead. The new `better-supabase/sql` subpath exports the SQL kit (`renderKit`, `kitLayout`, `compileReadSets`), and `better-supabase/config` now exports the snapshot types, `DEFAULT_CLAIMS` and `tenantClaimPaths`.

  The library no longer has `@supabase/config` as an optional peer; only the CLI reads `supabase/config.toml`.
- Doctor BS213 warns when `anon` or `authenticated` may insert or update a column that RLS helpers read to decide access, such as `memberships.role` or `contacts.customer_id`, and a policy lets them write the row. It also checks the `decidingColumns` in PermDock's manifest and names PD028. The finding lists the revoke and the grant of the remaining columns. Snapshots now record column-level insert and update grants (`columnGrants`); older snapshots only show table grants.
- Doctor treats `security definer` functions and functions with a `set` option as not inlinable (BS205, BS206), and its advice for them now points to `column in (select helper())`. New checks: `auth.role()` (BS109), update policies without a select policy or `with check` (BS110), needless and unused API grants (BS111), exposed security definer functions that never check the caller (BS112), storage inserts without the upsert policies (BS113), helpers that read `user_metadata` (BS114), zero-argument helpers called without `select` (BS215), foreign keys without an index (BS216, replacing splinter's lint for the same table), tenant foreign keys that can cross tenants (BS217), soft-delete tables without a partial index (BS218), containment filters without GIN (BS219), column types to avoid (BS220) and direct connections in serverless apps (BS221). BS211 also reports `idle_in_transaction_session_timeout`.

  Snapshots now record each index's access method and predicate, and who among `anon` and `authenticated` may execute the functions doctor reads. Both fields are optional in `snapshot-v2.json`, so older snapshots still load.
- The `entitlements` SQL kit module reads memberships from PermDock when `permdock.manifest.json` is present: `has_entitlement` checks `<rls.schema>.member_<scope>_ids()`, `feature_claims` reads `member_<scope>_ids_for(user_id)` from PermDock's hook, and `entitlement_members` reads the manifest's membership tables. `sql add entitlements` then no longer adds the `tenant` module or prints the hook note. The scope defaults to `organization`; set `entitlements.permdock: { scope }` for another of the manifest's scopes, or `entitlements.permdock: false` to keep `better_supabase.memberships`. The new doctor check BS408 warns when the manifest or the database lacks one of the two helpers.
- Cursor pagination no longer skips rows whose sort column is null: the next page follows where Postgres places nulls (last for `asc`, first for `desc`, or the `nulls` option). On the `better-supabase/postgres` executor a cursor over columns that sort the same way and are not nullable compiles to a row comparison such as `(name, id) > ($1, $2)`, which one index range scan can serve.

  `defineListQuery`, `defineResource`, `createOpenApi` and the MCP table tools accept `pagination: "cursor"`. The list then takes `after` instead of `page`, returns `nextCursor` and `hasMore`, keeps `size` capped by `maxPageSize`, and documents the cursor in its OpenAPI parameters and JSON Schema. `paginate` and offset lists work as before.
- The `audit`, `webhook-inbox` and `jobs` SQL kit modules add `purge_audit_log`, `purge_webhooks` and `purge_job_archive`. Each deletes rows older than an interval in batches and returns how many it deleted, for nightly pg_cron jobs. Only `service_role` can execute them. Run `better-supabase sql add` again to update the kit files.
- Security fixes in the SQL kit. Rerun `better-supabase sql add` for the modules you installed to apply them:

  - `create_invitation` no longer lets an admin invite someone as `owner`; only an owner or the service role can. The service-role check reads `auth.jwt() ->> 'role'` instead of the deprecated `auth.role()`, and `invitations.role` gets the same check constraint as `memberships.role`.
  - `accept_invitation` requires the signed-in user's address in `auth.users` to be confirmed, not only an `email` claim. An unconfirmed user gets the hint `INVITATION_EMAIL_UNCONFIRMED`.
  - `anon` can no longer call `has_org_role`, and the pgTAP kit's `tests.create_user` is granted to `authenticated` and `service_role` only.
  - The tenant module adds `member_org_ids(roles)`, a set-returning helper. Write policies as `org_id in (select better_supabase.member_org_ids())`, which Postgres evaluates once per statement instead of once per row.
  - Deduplicated jobs get a partial index on `dedupe_key` in each queue table, so `enqueue_job` no longer scans the queue while it holds the advisory lock.
  - `triggerSql` puts the realtime trigger function in the `better_supabase` schema, which the Data API does not expose, instead of `public`.

  `better-supabase gen` names a composite foreign key that repeats a column on both sides, such as `(customer_id, organization_id)` referencing `(id, organization_id)`, after the remaining column: the relation is `customer`, as it would be for a plain `customer_id` key. Schemas with such keys get new relation names; set `tables.<name>.relations` to keep the old ones.
- `createMcp` takes `allowedHosts`, which rejects requests whose `Host` header names another host (DNS rebinding protection, next to `allowedOrigins`), and `resourceDocumentation`, published as RFC 9728 `resource_documentation` in the protected resource metadata.
- `next.cached()` takes `tags` and `life.stale`. `tags` adds cache tags to the entry next to `bs:session:<user id>`, and `life.stale` caps the stale time `sessionStale` computes, so `next.cached({ tags: [snapshotTag(sub)], life: cacheLifeFor(snapshot) })` caches a PermDock snapshot no longer than the token or the snapshot. `next.invalidateSession(userId, { tags })` also expires the extra tags. PermDock can now drop the "Planned in better-supabase" note in its `guides/next-cache-components.mdx`.
- Doctor and `gen` read PermDock's `permdock.manifest.json` and `permissions.catalog.json` (paths set by `permdock.manifest` and `permdock.catalog` in the config). BS407 recognizes PermDock's hook by the manifest or its `-- permdock:hook v1` marker, treats functions in `supabase.hook.claims` as the hook's own sources, flags a wrapper that writes those claims again, and reports an info finding when `permdock.config.ts` has no manifest. BS405 takes PermDock's budget from the manifest. The new BS214 reports bucket and topic policies that pass a permission with `rowConditions: true` to PermDock's helpers, `gen` refuses to write such bucket policies, and `defineBucket` and `defineTopic` throw for those keys when given the catalog as `catalog`. The MCP recipe narrows `tool.meta` with PermDock's `isPermission` before `can` and `mayUse`.
- Support the Supabase CLI's pg-delta engine and native local stack. When `supabase/config.toml` sets `[experimental.pgdelta] enabled = true`, `better-supabase sql add` and doctor (BS304, BS305, BS404 and `--fix-grants`) name `supabase db schema declarative sync` instead of `supabase db diff`, BS404 asks for the grants in the schema file that defines the hook, and the declarative schema files are read from `declarative_schema_path` in name order, since pg-delta ignores `schema_paths`. `better-supabase env` falls back to `supabase status --env` when `[experimental] stack = true` makes `supabase status -o json` fail.
- `createPostgres` applies Supabase's role timeouts per transaction: `statement_timeout` 8 s for `asUser` and 3 s for `anon`, because `set role` skips the role's own setting. `statementTimeout` takes a number for every role or one value per role (`admin`, `authenticated`, `anon`). New options: `idleInTransactionTimeout`, `connectionTimeout` and `idleTimeout` (both default to 10 s). Each transaction now sets its timeouts, claims and role in one query after `begin`.
- `createPostgres({ pool })` runs on an existing `pg.Pool` or any object with `connect()` and `end()`, typed as the new `PgPool` and `PgPoolClient` exports of `better-supabase/postgres`. `list.parse()` now reads a typed `ListQueryInput` such as `{ page: 2, size: 10 }` instead of treating it as URL search params and falling back to page 1, and a non-string `q` such as `{ q: 5 }` reports `Must be text` instead of being accepted. `contextFromSupabase` throws a `TypeError` for an auth mode it does not know instead of returning it as the request context. The standards page lists the conformance test behind each adopted standard.
- Doctor reads the declarative schemas in `[db.migrations] schema_paths` order, then the files no entry matches, then the migrations newest first, and the built-in `config.toml` parser reads arrays over several lines. `sql add` names the kit files no `schema_paths` entry matches, because `supabase db diff` would skip them. `doctor --fix-grants` prints the grant and revoke SQL BS404 asks for as one block to append to the migration `supabase db diff` wrote. For PermDock's hook, BS404 points to `permdock supabase hook generate --grants-out` instead, and when a `-- permdock:grants v1` migration already grants the function, it says to apply the migrations.
- Breaking: time values in the public API are now `Temporal` values instead of `Date` objects and epoch numbers.

  - The `codecs.timestamptz` option takes `'instant'` instead of `'date'`. `timestamptz` columns decode to `Temporal.Instant`, `timestamp` columns to `Temporal.PlainDateTime`, and both keep microseconds. Rename the option and run `better-supabase gen`.
  - The `now` options of `defineSupabase`, plugin hooks, `toCloudEvents`, `forwardMutations`, `verifyWebhook` and `bucket.sweep` return a `Temporal.Instant`.
  - `Job.enqueuedAt`, `Job.visibleUntil`, `InboxMessage.receivedAt`, `EnqueueOptions.runAt`, the verified webhook `timestamp` and the `signWebhook` `timestamp` are `Temporal.Instant`.
  - `bucket.sweep({ olderThan })` takes a `Temporal.Duration` or a `Temporal.Instant` instead of milliseconds.
  - TypeScript 5.9 is no longer supported, because it has no Temporal lib. Use TypeScript 6 or 7.

  On Node 24, Safari and other runtimes without a native `Temporal`, install `temporal-polyfill` and import `temporal-polyfill/global` once at startup. Without it, the calls that need `Temporal` return a `DbError` that names the import. Auth keeps its `now` option in epoch milliseconds.
- The PermDock docs and the plugins skill reference match current PermDock. With `supabase.hook.claims: { features: 'better_supabase.feature_claims' }` in `permdock.config.ts`, PermDock's hook writes the `features` claim, so `hasEntitlement(session, ...)` works next to PermDock. The MCP recipe answers `visible` with PermDock's `mayUse`, and the Storage and Realtime pages point to the catalog's `rowConditions` and `permdock doctor` PD037 for permissions the helpers don't fully check.
- Two public types no longer rely on DOM-only globals. The `headers` option of `problem()` takes what the global `Headers` constructor accepts, and the JSON Web Keys in `better-supabase/testing` use the `node:crypto` type, so both resolve in a project whose `lib` leaves out `"DOM"`.
- The `better-supabase` skill's schema workflow now asks for RLS, policies, policy indexes and Data API grants on every new table, and points to Supabase's own skills. The CLI asks for an access token scoped to the project when it reads a hosted project.
- `better-supabase gen` uses `@supabase/postgrest-typegen` 0.3.1, which still produces the same `database.types.ts` as `supabase gen types` from Supabase CLI 2.119. Version 0.4.0 adds a `ComputedFields` key that the Supabase CLI does not emit yet, so it waits until the CLI catches up. The optional `@supabase/config` peer now accepts 0.11.

## 0.2.0 (2026-09-30)

- `createMcp` takes optional per-tool authorization hooks. `authorize(ctx, tool, args)` runs after the arguments are validated and before `run`, and returns `{ allowed: true }` or `{ allowed: false, reason?, scopes? }`. A refusal is a tool error, and a refusal with `scopes` is a 403 `insufficient_scope` challenge that lists the scopes the call needs. `visible(ctx, tool)` filters `tools/list`, and a hidden tool is called like an unknown one. `defineTool` and `mcp.tool` accept an opaque `meta`, for example a PermDock permission, which both hooks receive and clients never see. New types: `ToolRef` and `ToolDecision`. The PermDock guide has a recipe that checks PermDock permissions through a structural type.
- Align with PermDock's authorization contract, so a project can use better-supabase and PermDock on the same claims. The migration guide at https://bettersupabase.com/docs/migration/0.1-to-0.2 lists every step.

  Breaking changes:

  - The active tenant claim is `tenant_id` instead of `org_id`, in the token and in `app_metadata`. The new `claims` block in `better-supabase.config.ts` (`claims: { tenant, scope, features }`) renames it for the tenant plugin, the SQL kit, storage and realtime at once. `plugins.tenant.claim` is removed.
  - SQL kit: `better_supabase.current_org_id()` is now `current_tenant_id()`. `membership_claims()` moves to the tenant module and returns PermDock's `[{ scope, id, roles }]`. Plan features move out of memberships into `feature_claims()` in the entitlements module, which fills the `features` claim (`{ [tenantId]: string[] }`).
  - `MembershipClaim` has PermDock's shape (`scope`, `id`, `roles`, and optional `within`, `via`, `expiresAt`). `hasEntitlement` and `EntitlementKey` read the `features` claim.
  - `asUser` signs ES256 tokens with the key from `better-supabase keys` (`signing_keys_path` in `supabase/config.toml`), like a hosted project. `{ alg: 'HS256' }` keeps the shared secret and only works against a local stack.
  - `SPEC_PINS.mcp` and `MCP_PROTOCOL_VERSION` are `2026-07-28`. `createMcp` serves stateless requests (`server/discover`, request `_meta`, `Mcp-Method` and `Mcp-Name` headers) and still answers `initialize` for `2025-11-25`, `2025-06-18` and `2025-03-26` clients. A 403 carries an `insufficient_scope` challenge.
  - BS405 measures the whole token against 2 KB and, when the project has a `permdock.config.ts`, `memberships` plus `attrs` against PermDock's 1 KB budget (`doctor.claimsLimit` overrides the budget, or the whole-token limit without PermDock).

  New:

  - `sb.userMetadata(schema)` parses `user_metadata` into a typed `session.profile` for display. Metadata that fails the schema leaves `profile` undefined and logs one warning with the failing paths. No authorization code reads it. `ProfileOf<B>` in `better-supabase/react` types `useSession` from `createHooks`.
  - Buckets take a PermDock policy (`{ permdock: { read, write }, scope }`) and topics a `permdock: { receive, send, scope }` option. The generated policies check PermDock permissions through its `permitted_<scope>_ids()` or `permdock_has()` helpers instead of the tenant claim.
  - `sql add tenant` stops when a `permdock.config.ts` exists, unless you pass `--force`. Doctor BS407 reports a hook that calls `membership_claims` or writes PermDock's claims next to PermDock.
  - `better-supabase/testing` exports `signLocalJwt`, `localSigningKey`, `signTestJwtWithKey` and the `SigningJwk` type.
  - A new docs page, https://bettersupabase.com/docs/auth/permdock, shows both packages in one project.
- Doctor BS405 now measures what PermDock's budget covers. With a `permdock.config.ts`, it warns when `memberships` plus `attrs` from the hook's output pass 1024 bytes (or `doctor.claimsLimit`), measured with `octet_length` as PermDock's hook measures `supabase.hook.budget`. The whole-token check at 2048 bytes is a separate warning, so a normal PermDock token of about 1.5 KB no longer trips it. Without PermDock, `doctor.claimsLimit` still limits the whole token. `memberships_truncated` is reported as before.
- Entitlements are no longer treated as a PermDock conflict, because `features` is not a PermDock claim.

  - Doctor BS407 reports a custom access token hook next to PermDock only when it calls `better_supabase.membership_claims` or writes `roles`, `user_role`, `memberships` or the configured tenant claim itself. It no longer reports `feature_claims`, and it leaves PermDock's generated hook alone.
  - `sql add entitlements` works next to a `permdock.config.ts` without `--force`. It writes `tenant` as a dependency and prints a note. Only `sql add tenant` still needs `--force`.
  - The PermDock and entitlements docs say what works today. `has_entitlement(tenant, key)` and `tenant_entitlements(tenant)` work in SQL and RLS without a claim. `hasEntitlement(session, ...)` needs the `features` claim, which PermDock's hook doesn't write yet, so read entitlements from the database on the server until PermDock adds a hook slot for it.
- The PermDock guide lists every claim PermDock's generated hook writes (`user_role`, `roles`, `memberships`, the tenant claim, `attrs`, `authz_ver` and `memberships_truncated`). The migration guide and the `sb.userMetadata()` TSDoc say that `session.profile` is for display only, and that roles, memberships, the tenant and entitlements never come from it.
- The storage and realtime docs say that the `permdock` policy mode compares ids as text, so a path or topic segment must be the id's canonical lowercase form: an uppercase uuid is denied. An integration test covers it for buckets and topics.
- The docs now name the right PermDock command for the SQL helpers. `permdock_has` and `permitted_<scope>_ids` come from `permdock rls generate`, not from `permdock supabase hook generate`. The PermDock guide gains a setup step that runs both commands, and says that the helpers live in PermDock's `rls.schema`, which must equal the `schema` option on buckets and topics.
- Document that the `permdock` policy mode for buckets and topics only fits permissions whose grants have no row conditions beyond the scope. PermDock's helpers check role and scope, so a permission with row conditions (for example `ownerId = principal.id`) would grant every object in the scope. Leave those to the policies `permdock rls generate` writes. The storage, realtime and PermDock docs pages show a wrong and a right example, and the TSDoc on the `policy` and `permdock` options says the same.
- The PermDock guide says that a non-default `claims.tenant` must also be set as PermDock's `rls.tenantClaim` and passed to `subjectFromSupabase` or `subjectFromSupabaseSession` as `{ tenant }`, so both packages read and write the same tenant claim.
- The docs site answers questions with Ask AI, shows the last-updated date on every page, and has Open Graph images, a sitemap, type tables generated from the source, and links that add the docs MCP server to Cursor and VS Code. The repository now has a root `CHANGELOG.md`, and its fixture schema is declarative, with pgTAP tests for RLS. The published package does not change.

Every release of better-supabase, newest first. `pnpm version-packages` adds a
section from the pending changesets. Releases up to 0.1.0 are listed in
[packages/better-supabase/CHANGELOG.md](packages/better-supabase/CHANGELOG.md).
