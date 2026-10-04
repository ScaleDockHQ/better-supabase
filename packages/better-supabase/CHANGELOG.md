# better-supabase

## 0.5.1

### Patch Changes

- [`597ed8c`](https://github.com/ScaleDockHQ/better-supabase/commit/597ed8c6d8e9602b190445ad801084dc1cfda806) Thanks [@martijn00](https://github.com/martijn00)! - Breaking (types): `SessionActor` is a union on `kind`: `oauth-client` (with `chain`), `support` (with `sessionId`, `readOnly` and `reason`) and `impersonation` (with `reason`), and `Impersonator` gains `kind`. An exhaustive `switch` on `session.actor.kind` needs the two new cases.
  
  Support sessions and impersonated sessions mark their `act` claim: `supportClaims` writes `act.kind: "support"` and `actingAs` writes `act.kind: "impersonation"`. `actorOf` reads them as their own actor kinds instead of OAuth clients, `session.impersonator` follows `actorOf`, so an OAuth client or agent chain is no longer shown as an impersonator, and `session.delegation` and the `scopes` guard apply to `oauth-client` actors only. An `act` with another `kind`, or a support level without `session_id`, makes the session invalid (`reason: 'actor'`). A support token minted by 0.5.0 (`session_id` without `kind`) still counts as a support session until 0.6. `supabaseClaimFixtures` from `better-supabase/testing` holds a support session (writable and read-only), an impersonated session, an OAuth client and an agent chain, each valid against PermDock's `supabase-claims-v1.json`.

- [`597ed8c`](https://github.com/ScaleDockHQ/better-supabase/commit/597ed8c6d8e9602b190445ad801084dc1cfda806) Thanks [@martijn00](https://github.com/martijn00)! - Breaking: `allow: ['anon']` no longer admits users from `signInAnonymously()`. Only `'anonymous'` admits anonymous sign-ins, and `'anon'` means a caller without a session. `['anonymous']` alone now admits anonymous sign-ins and refuses other users; before, it admitted nobody. A route that serves guests next to signed-in users lists `['user', 'anonymous']`, and a public route that also serves guests `['user', 'anonymous', 'anon']`. With PermDock, pair the default `allow` with `rls: { anonymousSignIns: 'deny' }` in `permdock.config.ts`.

- [`597ed8c`](https://github.com/ScaleDockHQ/better-supabase/commit/597ed8c6d8e9602b190445ad801084dc1cfda806) Thanks [@martijn00](https://github.com/martijn00)! - The entitlements module in PermDock mode reads `entitlement_members()` from the manifest's `rls.memberships` entries for its scope, the tables PermDock's `member_<scope>_ids_for` reads, and falls back to the hook's membership sources only for a manifest without `rls.memberships`. Doctor (BS408) warns when `rls.memberships` maps no table to the scope, and notes the fallback.

- [`597ed8c`](https://github.com/ScaleDockHQ/better-supabase/commit/597ed8c6d8e9602b190445ad801084dc1cfda806) Thanks [@martijn00](https://github.com/martijn00)! - The `permdock` access model reads PermDock's manifest itself. `better-supabase sql add` takes the helpers' schema from `rls.schema`, the scope from the root `rls.scopes` entry (the one without `within`) and the id type from that scope's `type`, whatever `entitlements.permdock` says, so a manifest with `rls.schema: "authz"` and a root scope `tenant` gets `authz.permitted_tenant_ids`. It stops instead of guessing when the manifest is missing, has no single root scope, or disagrees with `kits.access.permdock.scope`, `kits.access.permdock.schema` or `kits.access.idType`; 0.5.0 fell back to `permdock.permitted_organization_ids` and `uuid`. Code that renders the kit without the CLI (`renderKit`, `moduleBody`) now sets both `kits.access.permdock.schema` and `kits.access.permdock.scope`. Doctor reports the same problems, and helpers the manifest or the database lacks, as the new BS411 error.

- [`597ed8c`](https://github.com/ScaleDockHQ/better-supabase/commit/597ed8c6d8e9602b190445ad801084dc1cfda806) Thanks [@martijn00](https://github.com/martijn00)! - Under the `permdock` access model, `can_user()` and `member_can()` raise SQLSTATE `0A000` (hint `ACCESS_CALLER_ONLY`) for anyone but the caller instead of returning `null`, because PermDock's helpers read `auth.uid()`. The invitations module no longer re-checks the inviter's permission when an invitation is accepted, and the notifications module no longer filters recipients by their read permission, under that model; in 0.5.0 the re-check passed silently on the `null` answer, and the filter dropped every recipient but the sender. Check both in the app when they matter. Run `better-supabase sql add` to rewrite the installed files.

- [`597ed8c`](https://github.com/ScaleDockHQ/better-supabase/commit/597ed8c6d8e9602b190445ad801084dc1cfda806) Thanks [@martijn00](https://github.com/martijn00)! - The access kit docs, the `canAssign` JSDoc and the `can_assign()` SQL comment recommend PermDock's assignment rule for the `permdock` model: `canAssign: "permdock.permdock_can_assign({role}, {tenant}::text)"`, with the manifest's `rls.schema`. This is the assignment rule the 0.5.0 note "the `permdock` and `custom` access models need an assignment rule" refers to; see [the access kit](https://bettersupabase.com/docs/kits/access#permdock). Without it only the service role assigns roles, since PermDock projects don't install the `tenant` module, and doctor (BS411) warns.

- [`597ed8c`](https://github.com/ScaleDockHQ/better-supabase/commit/597ed8c6d8e9602b190445ad801084dc1cfda806) Thanks [@martijn00](https://github.com/martijn00)! - Under the `permdock` access model, `better-supabase sql add` and doctor (BS411) check every permission key the kit modules check against `permissions.catalog.json`, platform keys for `permdock_has` included. A key must be `rowConditions: false`, because PermDock's helpers check role and scope only; a key with row conditions, without the flag or missing from the catalog stops `sql add`. `kitPermissionKeys(kits, names)` from `better-supabase/sql` lists the keys with their module, action and scope, and `kitFilePaths(names, layout)` lists the files a set of modules writes without rendering them, so `sql list` works while the access settings are incomplete.

- [`023474d`](https://github.com/ScaleDockHQ/better-supabase/commit/023474d48f930f706167557ecf85d51013f513bd) Thanks [@martijn00](https://github.com/martijn00)! - `better-supabase gen` uses `@supabase/postgrest-typegen` 0.4.0. `database.types.ts` gains a `ComputedFields` key on every table and view: the names of its computed fields, or `never`. postgrest-js reads it to leave computed fields out of `select('*')`, and row-typed function arguments no longer include them. Run `better-supabase gen` to regenerate. Supabase CLI 2.119 doesn't write `ComputedFields` yet, so until it does, `supabase gen types` output differs from `gen` by that key.

- [`3e1472a`](https://github.com/ScaleDockHQ/better-supabase/commit/3e1472afeb8160ec41c7a05b663fec1818988605) Thanks [@martijn00](https://github.com/martijn00)! - The optional `oxfmt` peer accepts any version from 0.66.0 below 1.0, so `pnpm add -D oxfmt` installs the latest. The runtime dependencies are ranges instead of exact versions: `@supabase/postgrest-js ^2.116.0` (the floor of the `@supabase/supabase-js` peer), `@supabase/ssr ^0.12.7`, `@supabase/server ^1.9.0`, `@supabase/middleware ^1.0.0` and `@standard-schema/spec ^1.1.0`, so an app shares one copy of each with its own Supabase packages. `@supabase/postgrest-typegen` stays an exact version.
  
  The `canAssign` JSDoc no longer says it defaults to true. The `custom` access model requires it. Without it, the `permdock` model lets only owners assign the owner role when the `tenant` module is installed, and lets only the service role assign roles when it isn't. The access kit docs now say the same, and their `custom` example sets `canAssign`, which that model requires.

## 0.5.0

### Minor Changes

- [#24](https://github.com/ScaleDockHQ/better-supabase/pull/24) [`5c3143e`](https://github.com/ScaleDockHQ/better-supabase/commit/5c3143eebcfaebf191185679fab9464abd16bc60) Thanks [@martijn00](https://github.com/martijn00)! - Guards refuse anonymous users (`signInAnonymously()`, the `is_anonymous` claim) with a 403 `ANONYMOUS_USER` unless `allow` lists `'anonymous'` or `'anon'`, `toSession()` adds `anonymous`, and the `realtime-tables` kit module sends anonymous users no change signals. Before 1.0 this minor release is the breaking slot: routes that served guest sessions need `allow: ['user', 'anonymous']`.
  
  The framework adapters agree with each other. `ctx.apply(response)` adds refreshed session cookies and, after a write, `bs-primary-until`, so Hono, edge and the new oRPC `bs.fetchHandler(handler)` keep read-your-writes like Next.js does. MCP reads the session from the `Authorization` header only, answers an unreachable JWKS with a 503 instead of a scope challenge, sends a missing second factor as a plain 403, takes `advertisedScopes` (with `scopes` as a deprecated alias) and enforces `requiredScopes`. REST resources refuse cross-site form posts that ride on the session cookie (`CROSS_SITE_REQUEST`) and answer malformed keys and bodies with `invalid_input`, whose detail survives in production. Hono's `bs.onError` returns an `HTTPException`'s own response, Next.js route handlers turn unexpected throws into a 500 Problem Details response while `redirect()` and `notFound()` still work, and `contextForSession` requires the token's auth kind to match the session. `createServer` takes `fetch` for its PostgREST and supabase-js clients, the `auth` event carries `reason` and `rawSource`, the `react-server` build exports `hasEntitlement` and `useLiveCount`, and every adapter builds the user actor, impersonator included, from one function.

- [#25](https://github.com/ScaleDockHQ/better-supabase/pull/25) [`b6a98a1`](https://github.com/ScaleDockHQ/better-supabase/commit/b6a98a102fa0df347da310daf5cac6d669e9028f) Thanks [@martijn00](https://github.com/martijn00)! - The `audit` SQL kit module can adopt an existing audit table (`kits.audit.tables` and `columns`), and `audit()` takes `redact`, `category`, `event_prefix`, `target_type` and `tenant_column`. The new `audit_event` function records events that are not row changes, with an idempotency key. The options `appendOnly`, `readPolicy`, `impersonators`, `restricted`, `eventRoles`, `eventCategory` and `eventSource` add an append-only guard, a tenant read policy, hidden impersonation columns and a separate table for sensitive details. `purge_audit_log` honours an `audit_retention(tenant)` SQL hook, and `purgeAuditLog` from `better-supabase/jobs` takes a per-tenant retention callback. Run `better-supabase sql upgrade` to move from version 1.

- [#24](https://github.com/ScaleDockHQ/better-supabase/pull/24) [`5c3143e`](https://github.com/ScaleDockHQ/better-supabase/commit/5c3143eebcfaebf191185679fab9464abd16bc60) Thanks [@martijn00](https://github.com/martijn00)! - `better-supabase/hono` adds `bs.app()`, a `Hono` app typed with the adapter's `Env` and with `bs.onError` installed, and the type-only `bs.Env` for apps that build their own. After `@supabase/server`'s `withSupabase`, `bs.middleware()` reuses its verification of the bearer token when the stored claims are that token's payload, then runs its own claims, `act` and `userMetadata` checks.
  
  `clearOnUserChange(queryClient, auth)` in `better-supabase/query` removes the `["bs"]` queries when the signed-in user changes, for apps without React; `BetterSupabaseProvider` uses it.
  
  A bucket with `tenant` now checks paths on the client too: `upload`, `download`, signing, `remove`, `reserve` and `list` refuse a path in another tenant's segment, or any path when the connection has no tenant, with a `forbidden` error before calling Storage. Pass `{ context }` or `{ tenant }` to `connect()`, or `{ allTenants: true }` for cross-tenant admin work; `deleteAccount` does the latter. `client.path(target)` returns the checked path.
  
  Jobs record the enqueuing request's actor and tenant: `enqueue(queue, payload, { context })` and `schedule(..., { context })` store them next to the payload, and the handler gets them as `job.context`, ready for `db.$with(job.context)`. A job without a tenant gets the `tenant()` plugin's `onMissing` unless the worker runs with `allTenants: true`.
  
  `actor()` fills an `impersonatedBy` column (generated from `impersonated_by`, the column the SQL kit's `track_actor` stamps) from the impersonating admin, and clears it on writes without one.
  
  Event sink sends are tracked on `betterSupabase.events` (`pending`, `settled()`). Next.js routes and actions hand them to `after()`, and edge handlers to `waitUntil`: the Workers `ctx`, or `createEdge(..., { waitUntil })` on Supabase.
  
  The PermDock guide has oRPC and Hono recipes that refuse a procedure or route without a permission.

- [#25](https://github.com/ScaleDockHQ/better-supabase/pull/25) [`b6a98a1`](https://github.com/ScaleDockHQ/better-supabase/commit/b6a98a102fa0df347da310daf5cac6d669e9028f) Thanks [@martijn00](https://github.com/martijn00)! - Jobs run without pgmq or pg_cron when you want. `kits.jobs.options.backend: "table"` stores jobs in `better_supabase.job_messages` and claims them with `for update skip locked`, and `kits.jobs.options.scheduler: "drain"` stores schedules with a time zone each. `jobs.drainRoute({ secret, handlers })` is a route for Vercel Cron that enqueues due schedules and drains queues within a time budget, and `drain` takes a `budgetMs`. `schedule` takes `{ timeZone }` and validates the cron expression first. `createJobs` accepts any `QueueBackend` (API version 1), with `sqlQueueBackend`, `pgmqPublicBackend` and the `testQueueBackend` conformance kit. The `jobs` module is now version 2: `better-supabase sql upgrade` drops the old four-argument `schedule_job`.

- [#26](https://github.com/ScaleDockHQ/better-supabase/pull/26) [`3a2d251`](https://github.com/ScaleDockHQ/better-supabase/commit/3a2d25131b296ab1ff8c8aebf16aa9b7e1a2806b) Thanks [@martijn00](https://github.com/martijn00)! - The SQL kit's rows and role settings, which a schema diff can't capture, move to `supabase/better-supabase-data`, and the new `better-supabase sql data` writes them into a migration stamped after the newest one. `rate-limit` sets `pgrst.db_pre_request` that way, and doctor BS313 warns when the live database never calls `check_request()`. `sql upgrade` writes next to the located `config.toml`, and each module rejects options it doesn't declare.
  
  Breaking: `entitlements` no longer defaults `entitlements.customer` to `organizations.stripe_customer_id`. It reads the managed `organizations` module's column when that module is installed; otherwise `sql add` stops until you set it. `tenant_ids_with_entitlement(key)` gives policies a set check.
  
  Jobs enforce max attempts at claim, retry with full jitter and replay dead letters (`replay_dead_job`, `jobs.replay`). The outbox orders by `(xid, position)` and gives events uuid ids. Outgoing webhooks take a lease token, follow the Svix retry schedule with `Retry-After`, and disable a destination after failing for `disableAfter`. Notifications back off between deliveries and fail them after `max_attempts`. Key indexes lead with the key, webhook policies read `tenant_ids_with()` once per statement, `jsonb-schemas` adds its checks `not valid` and validates them separately, and `purge_rate_limits()`, `purge_webhook_deliveries()` and `purge_notifications()` join the other purges.

- [#25](https://github.com/ScaleDockHQ/better-supabase/pull/25) [`b6a98a1`](https://github.com/ScaleDockHQ/better-supabase/commit/b6a98a102fa0df347da310daf5cac6d669e9028f) Thanks [@martijn00](https://github.com/martijn00)! - Kits share one set of extension points: typed events, policy callbacks, SQL hooks and fixed attribute names.
  
  - `betterSupabase.on("kit", handler)` receives `support.*`, `org.*`, `invitation.*`, `notification.*` and `webhook.*` events with a copy of their data. `onKitEvent(betterSupabase, "support.*", handler)` from `better-supabase/events` filters by type or prefix and types the data.
  - `forwardKitEvents()` and `kitCloudEvent()` send kit events to an `EventSink` as CloudEvents, and `traceKitEvents()` from `better-supabase/otel` records them with the `KIT_ATTRIBUTES` names (`better_supabase.org.id`, `better_supabase.support.session_id`, ...).
  - Policy callbacks (`Policy`, `PolicyDecision`) fail closed: only `true` allows, and a throw or rejection denies.
  - `kits.<module>.hooks` sets where a module looks for the app's `before_*` and `after_*` SQL functions, and `kits.<module>.events: false` stops it writing its events to the outbox.

- [#26](https://github.com/ScaleDockHQ/better-supabase/pull/26) [`3a2d251`](https://github.com/ScaleDockHQ/better-supabase/commit/3a2d25131b296ab1ff8c8aebf16aa9b7e1a2806b) Thanks [@martijn00](https://github.com/martijn00)! - Breaking: the SQL kit fails closed. `current_tenant_id()` returns a tenant only while the caller is a member, the claim is cleared when a member is removed, and `kits.access.activeTenant` defaults to `'resolver'` (the tenant `ServerOptions.tenant` resolved, then the claim). Disabled organizations deny access, the `permdock` and `custom` access models need an assignment rule, and only an owner can transfer ownership. A member can never raise their own role or assign one above it.
  
  Platform invitations move to `platform_invitations` under a role ceiling that accept checks again, accept checks that the inviter can still assign the role, and `valid_for` is capped by `maxValidFor`. Support sessions refuse platform targets and writes by default and allow one active session per admin; a token with an `act` claim has no platform permissions.
  
  Doctor BS312 reports a kit schema listed in `[api] schemas`. `set_actor` keeps `created_by` on updates, `track_realtime` refuses a table without the tenant column, the rate limit and `request_ip()` use the right-most forwarded hop, audit is append-only by default, idempotency keys are scoped to the caller, public buckets get no select policy, members see only public profile columns, and outgoing webhooks follow no redirects, cap the response body and use 32-byte secrets.

- [#26](https://github.com/ScaleDockHQ/better-supabase/pull/26) [`3a2d251`](https://github.com/ScaleDockHQ/better-supabase/commit/3a2d25131b296ab1ff8c8aebf16aa9b7e1a2806b) Thanks [@martijn00](https://github.com/martijn00)! - Breaking: the SQL kit follows one naming standard. Run `better-supabase sql upgrade`, then `sql sync` and `sql data`; the [0.4 to 0.5 guide](https://bettersupabase.com/docs/migration/0.4-to-0.5) lists every step. The forward steps rename `memberships.org_id` and `invitations.org_id` to `organization_id`, `better_supabase.audit_log` to `audit_events` (with `occurred_at` and `organization_id`, and a read-only `audit_log` view until 0.6), and `audit_trigger()` to `audit_row_change()`. Doctor reports the old column names in your SQL (BS309), also when a column is unqualified next to its table.
  
  The modules new in this release use the same names: `webhook_endpoints` with `event_types` and the statuses `pending`, `delivering`, `succeeded`, `retrying`, `dead` and `canceled`; notifications with `type`, `data`, `actor_id` and `user_id`, and `types` instead of `kinds` in `createNotifications`. Permission keys follow `<area>.<verb>`, and managed tables get `updated_at` triggers and indexes on their foreign keys.
  
  Breaking: `toCloudEvents` and `kitCloudEvent` put the actor in `data.actorId` instead of the `actorid` context attribute, so user ids stay out of broker headers. The outbox relay prefixes event types with `dev.better-supabase`, and `webhooks.sink()` removes the prefix again.

- [#26](https://github.com/ScaleDockHQ/better-supabase/pull/26) [`3a2d251`](https://github.com/ScaleDockHQ/better-supabase/commit/3a2d25131b296ab1ff8c8aebf16aa9b7e1a2806b) Thanks [@martijn00](https://github.com/martijn00)! - The new `sessions` SQL module adds `better_supabase.session_active()` for restrictive policies: it is false once the token's session was revoked or expired, or the user is banned or deleted.
  
  Options that only exist to match an existing schema are accepted in `mode: "adopt"` only: `tokenStorage: "plain"` for invitations, `secretStorage: "column"` and non-`text` `eventIdType` or `runIdType` for webhooks-out, and `kitSource` or `defaultSource` for the outbox. Doctor BS314 warns about each until you remove it. `better-supabase/sql` exports `migrationOptionUses(kits)` to list them. The `assignmentCeiling` and `triggerPrefix` options, the invitations `errorCodes` option and `kits.access.disabled.tenantKey` are removed.

- [#25](https://github.com/ScaleDockHQ/better-supabase/pull/25) [`b6a98a1`](https://github.com/ScaleDockHQ/better-supabase/commit/b6a98a102fa0df347da310daf5cac6d669e9028f) Thanks [@martijn00](https://github.com/martijn00)! - SQL kit modules now fit existing schemas. `kits.<module>` in the config sets a module's mode (`managed`, `adopt` over your own tables, or `custom` where you write the contract functions), its schema, table and column names, tenant id type and permission keys. Each file's header records the module version and mode, and schema files record them in `better_supabase.kit_modules`. Doctor BS307 checks the functions of custom-mode modules, and BS304 points hand edits at `kits` instead.
  
  The new `access` module gives policies and kit modules one permission check, `can(scope, id, permission)`, with `tenant_ids_with()`, `is_platform()`, `can_user()`, `can_assign()` and `permission_claims()`. `kits.access.model` picks a role list from the config, role and permission tables with per-tenant overrides, PermDock or your own functions, and `kits.access.disabled` switches off tenants and users with a `disabled_at` column. The `tenant` module (version 2) takes its role names from `kits.access.roles`, adds `memberships.last_used_at` and `org_member_role()`, writes the memberships claim as an array or a map (`options.claimFormat`), and reads the active tenant from `kits.access.activeTenant`: a resolver (the default), the claim or a profile column.
  
  For resolvers, `createServer` takes `tenant: (request, auth) => id`, and `context()` takes `{ tenant }`. The tenant becomes `context.tenant`, the `better_supabase.tenant` setting over Postgres and the `x-bs-tenant` header (`TENANT_HEADER`) over the Data API. `postgres.asUser`, `executorFor` and `transaction` take `settings` and `readOnly`. Doctor BS308, with `--as <user id>`, warns when the access token hook writes no tenant claim while the claim is the active tenant.
  
  `better-supabase/config` exports the kit config types (`KitsConfig`, `KitModuleConfig`, `KitMode`, `AccessKitConfig` and `ActiveTenantSource`) for apps that build their `kits` config in a separate module.

- [#25](https://github.com/ScaleDockHQ/better-supabase/pull/25) [`b6a98a1`](https://github.com/ScaleDockHQ/better-supabase/commit/b6a98a102fa0df347da310daf5cac6d669e9028f) Thanks [@martijn00](https://github.com/martijn00)! - SQL kit modules have versions and an upgrade path, and a codemod rewrites renamed APIs.
  
  - `better-supabase sql upgrade` reads each module's `@bs-kit` version (a file without one is version 1), writes the forward steps into `supabase/migrations/<timestamp>_better_supabase_kit_upgrade.sql` and rewrites the module files. `--check` exits 1 when a module is behind or a file is stale.
  - Deprecated kit functions keep a wrapper under the old name until they are removed. `upgradePlan()`, `kitDeprecations()` and `moduleVersion()` are exported from `better-supabase/sql`.
  - `track_updated_at()` and `audit()` warn about an existing trigger that does the same work, and drop it with `replace_trigger => true`.
  - Doctor reports deprecated or removed kit symbols in schema files and policies (BS309), a kit trigger next to an equivalent one (BS310), and a module behind its version on disk or in `better_supabase.kit_modules` (BS311). BS304 skips files BS311 reports.
  - `better-supabase codemod <version>` rewrites imports, members, JSX props and call options for renamed APIs (`0.4`, and `0.5` for `createMcp`'s `scopes`), skipping strings and comments, and lists the lines it leaves for review. `--dry-run` prints the diff.

- [#25](https://github.com/ScaleDockHQ/better-supabase/pull/25) [`b6a98a1`](https://github.com/ScaleDockHQ/better-supabase/commit/b6a98a102fa0df347da310daf5cac6d669e9028f) Thanks [@martijn00](https://github.com/martijn00)! - Add the `notifications` SQL kit module and `better-supabase/notifications`. `notify(jsonb)` is a `security definer` sender that checks `notifications.send`, leaves out the actor and non-members, and applies subject subscriptions and per-channel preferences. `createNotifications` sends with typed data and reads, counts, marks, dismisses and resolves notifications; `deliver()` sends email, push and other channels through `NotificationChannel` implementations with leases and retries. `useNotifications` from `better-supabase/react` keeps a list current over a private Realtime topic. Existing tables work with `mode: 'adopt'`, and the topic and event names are configurable. `OrgsTransport` is now `KitTransport`, exported from both `better-supabase/orgs` and `better-supabase/notifications`.

- [#25](https://github.com/ScaleDockHQ/better-supabase/pull/25) [`b6a98a1`](https://github.com/ScaleDockHQ/better-supabase/commit/b6a98a102fa0df347da310daf5cac6d669e9028f) Thanks [@martijn00](https://github.com/martijn00)! - Organizations and invitations. The new `organizations` SQL kit module creates, updates and deletes organizations (hard or soft), changes member roles, removes members, transfers ownership and switches the active organization through `kits.access.activeTenant`. A deferred trigger keeps an owner in every organization, and a trigger stops members from raising their own role or assigning one above it. The `invitations` module moves to version 2: `invite_member` returns the invitation with its token, invitations can be resent, revoked, declined and previewed without a session, can carry `prefill` data and can target the platform under the catalog access model, and accepting re-checks that the inviter may still invite. `create_invitation` keeps its 0.4 signature. Both modules check permissions through the access contract, so `invitations` now needs `access`, and both support `mode: 'adopt'` with options for token storage, slug rules, error SQLSTATEs and extra columns. The new `better-supabase/orgs` subpath calls them with `createOrgs`, over Postgres (`sqlTransport`) or the Data API (`rpcTransport`), with `canInvite` and `onInvite` callbacks and `org.*` and `invitation.*` kit events, including the new `org.updated` and `org.deleted`. The `tenant` module now installs on a fresh database under `kits.access.model: 'catalog'`.

- [#25](https://github.com/ScaleDockHQ/better-supabase/pull/25) [`b6a98a1`](https://github.com/ScaleDockHQ/better-supabase/commit/b6a98a102fa0df347da310daf5cac6d669e9028f) Thanks [@martijn00](https://github.com/martijn00)! - Transactional outbox. The new `outbox` SQL kit module stores events with `emit_event(type, payload, subject, tenant, key, source)` in the writing transaction, deduplicates by key per tenant, adds `track_events(table)` row triggers and keeps events for `outbox_history` until `purge_outbox`. Named consumers read in order with their own cursor and a lease, and a claim never skips an event whose transaction is still open. The `organizations` and `support-sessions` modules write their events to it once it's installed. `createOutbox` in `better-supabase/jobs` emits, registers consumers, relays events as CloudEvents to any `EventSink` and serves `relayRoute` for a cron caller. The module supports `mode: 'adopt'` for an existing events table.
  
  The `defaultSource` option fills the source of `emit_event` calls that pass none, and `kitSource` sets the source kit modules write (`better-supabase/{module}` by default), so an adopted events table with a check on its source column keeps working. Adopt mode still creates the consumers table, since an existing app has no cursors yet.

- [#24](https://github.com/ScaleDockHQ/better-supabase/pull/24) [`5c3143e`](https://github.com/ScaleDockHQ/better-supabase/commit/5c3143eebcfaebf191185679fab9464abd16bc60) Thanks [@martijn00](https://github.com/martijn00)! - The PermDock integration fails closed in more places. Buckets and topics in `permdock` mode now call PermDock's helpers in `permdock`, PermDock's default `rls.schema`, instead of `public`; set `schema: 'public'` on the policy if your PermDock config writes them there. `gen` and doctor BS214 refuse PermDock bucket policies when `permissions.catalog.json` is missing, and the catalog must be version 1. `sql add entitlements` refuses a PermDock project without a manifest or `rls` block instead of falling back to the tenant module (set `entitlements.permdock: false` for that). BS214 also reports a helper schema other than the manifest's, a scope the manifest doesn't declare and a key checked at another scope than its catalog entry. BS408 checks that PermDock's hook fills `claims.features` from `better_supabase.feature_claims` and that a membership source covers the scope. The new BS409 reports a `claims.tenant` that differs from the manifest's `rls.tenantClaim`, PermDock markers other than v1 and a `claims.scope` that isn't the root scope. Scope id types `integer`, `int8` and other aliases are accepted, and MCP table tools take a permission per operation from the resource's `meta`.

- [#24](https://github.com/ScaleDockHQ/better-supabase/pull/24) [`5c3143e`](https://github.com/ScaleDockHQ/better-supabase/commit/5c3143eebcfaebf191185679fab9464abd16bc60) Thanks [@martijn00](https://github.com/martijn00)! - Plugins compose without holes. `timestamps()`, `actor()` and `softDelete()` refuse caller-supplied values for the columns they fill unless the call passes `{ override: true }`, and generated JSON Schema and OpenAPI documents mark those columns `readOnly`. On tenant tables, an upsert that updates on conflict needs the tenant column in its conflict target, the SQL executor guards the update with `where <tenant> = excluded.<tenant>`, a query whose includes reach a tenant table fails closed without a tenant, and numeric tenant columns compare by their text. An upsert that updates a soft-deleted row restores it.
  
  `rules()` runs before every other plugin. `noUnboundedFindMany` skips aggregates, `maxLimit` ignores `paginate()`'s look-ahead row, `requireTenantContext` reads the same claim paths as `tenant()`, and `noSensitiveSelect` checks reads only, because writes without a `select` no longer return sensitive columns. Offset `paginate()` orders by the primary key by default. `validation()` decodes codec columns (Temporal values, `bigint`) before validating and encodes them afterwards.
  
  Mutation events give hooks and listeners a copy of the rows, so they can't change the result (`testPlugin` checks this), and carry `intent` (`softDelete` for a delete that became an update), the affected primary `keys` when they are known, and the `tenant` that `tenant()` resolved. CloudEvents and cache invalidation use them, so soft deletes send `row.softdeleted` events and invalidate their rows. `defineReadSet` warns when query plugins scope tables its generated function reads. The audit kit keys entries by each table's primary key and reads the tenant column from `plugins.tenant.column`, and `gen` refuses a soft-delete column that isn't a timestamp.

- [#25](https://github.com/ScaleDockHQ/better-supabase/pull/25) [`b6a98a1`](https://github.com/ScaleDockHQ/better-supabase/commit/b6a98a102fa0df347da310daf5cac6d669e9028f) Thanks [@martijn00](https://github.com/martijn00)! - Profiles and image buckets. The new `profiles` SQL kit module creates a profile on sign-up from auth metadata (full, first and last name, avatar), allocates a unique username, mirrors `auth.users.email`, grants updates only on the columns users own and refuses changes to service-owned columns (`PROFILE_COLUMN_READONLY`). It supports `mode: 'adopt'` for an existing table keyed by any column, an `after_profile_sync` hook, extra columns, a read policy for people in the same organizations and `backfill_profiles()`. `better-supabase/storage` adds `avatarBucket()` and `orgLogoBucket()` presets and a bucket policy, `{ access: { read, write } }`, that checks permissions through the SQL kit's access contract.

- [#25](https://github.com/ScaleDockHQ/better-supabase/pull/25) [`b6a98a1`](https://github.com/ScaleDockHQ/better-supabase/commit/b6a98a102fa0df347da310daf5cac6d669e9028f) Thanks [@martijn00](https://github.com/martijn00)! - Support mode: platform admins can view the app as a user. The new `support-sessions` SQL kit module records sessions in a table (or an adopted one), checks `is_platform('support.start')`, writes `support.started` and `support.ended` to the audit log and can call your access token hook for the target's claims. `createServer` takes `support: supportSessions({ store, authorize, claims, policy, cookie })`, which apps without support mode never bundle; while the `bs-support` cookie names a running session, contexts, sessions, actions and routes run as the target over Postgres, read-only by default, with an `act` claim that carries the session id. Next.js gets `bs.startSupport()`, `bs.stopSupport()` and `supportTag()`, React gets `useSupportSession()`, and `better-supabase/testing` gets `testSupportSessionStore`. The audit module records the session in a new `support_session_id` column; an adopted table maps `supportSession` to `null` when it has none.

- [#24](https://github.com/ScaleDockHQ/better-supabase/pull/24) [`5c3143e`](https://github.com/ScaleDockHQ/better-supabase/commit/5c3143eebcfaebf191185679fab9464abd16bc60) Thanks [@martijn00](https://github.com/martijn00)! - Values from Postgres and the peer libraries no longer break responses. JSON responses from the server adapters and MCP write `bigint` values as decimal strings. A `timestamptz` or `timestamp` holding `infinity` comes back as an `invalid_value` error (status 500, with `column`) instead of throwing, because Temporal has no infinite value. Temporal values from another realm or a second polyfill copy are recognized by their `Symbol.toStringTag`, and Standard Schema issues with symbol path keys keep the error serializable.
  
  `loadEnv()` reads inline keys from `SUPABASE_JWKS`, as `@supabase/server` does, and verifies with them without fetching `jwksUrl`. The OpenTelemetry plugin writes `db.namespace` as `{database}|{schema}` (`postgres|public` by default, `otel({ database })` to change it), adds `server.address` and `server.port` from `otel({ server })` to spans and metrics, and sets `db.response.status_code` only for SQLSTATE codes. `BetterQueryMeta` builds on the app's `Register['queryMeta']`, and `send_email`'s `email_data` accepts fields Auth adds later.
  
  Doctor's BS410 reports HTTP auth hooks and checks their `v1,whsec_` secrets, and its custom access token hook event carries `iss` and `amr`. The peer ranges now state what the code needs: `pg >=8.15 <9`, `@tanstack/query-core ^5.62.0`, `@orpc/server >=2.0.0-beta.40 <3`, `hono <5`, `next <17`, `@opentelemetry/api <2`, and `oxfmt 0.66.0`, the version `@supabase/postgrest-typegen` pins; the `gen` notice and docs show how to allow a newer oxfmt.

- [#25](https://github.com/ScaleDockHQ/better-supabase/pull/25) [`b6a98a1`](https://github.com/ScaleDockHQ/better-supabase/commit/b6a98a102fa0df347da310daf5cac6d669e9028f) Thanks [@martijn00](https://github.com/martijn00)! - Add the `webhooks-out` SQL kit module and outgoing webhooks in `better-supabase/webhooks`. Destinations subscribe to event types (exact, `*` or `prefix.*`), secrets live in Supabase Vault (or a column) and rotate with an overlap, and every delivery is logged with its status, response and duration. `createWebhooks` publishes events idempotently, dispatches to one destination, and `deliver()` or `deliverRoute()` sends due deliveries with leases, retries with backoff, dead letters, redelivery and auto-disable after repeated dead letters. Requests are signed with Standard Webhooks by default or with `hmacSigner` for an existing format, and `publicUrl()` rejects private and local addresses, also on each redirect. `WebhookSigner`, `WebhookTransport` and `WebhookSecretStore` are versioned extension interfaces with conformance kits in `better-supabase/testing`. RLS policies in the `notifications` module now use `better_supabase.can`, which clients may execute, instead of `member_can`.

### Patch Changes

- [#22](https://github.com/ScaleDockHQ/better-supabase/pull/22) [`f8be1be`](https://github.com/ScaleDockHQ/better-supabase/commit/f8be1be21e0d860d241f6f87915b8ebc378381e1) Thanks [@martijn00](https://github.com/martijn00)! - The docs and skills follow the Naming page's file layout everywhere. The PermDock page defines `betterSupabase` in `src/lib/supabase/index.ts` and creates `bs` in `server.ts` and `client.ts`, and every Next.js `server.ts` starts with `import "server-only"`. The docs drift check now fails a code block that breaks the layout.

- [#22](https://github.com/ScaleDockHQ/better-supabase/pull/22) [`f8be1be`](https://github.com/ScaleDockHQ/better-supabase/commit/f8be1be21e0d860d241f6f87915b8ebc378381e1) Thanks [@martijn00](https://github.com/martijn00)! - Doctor BS404 and `doctor --fix-grants` follow pg-delta for PermDock's hook. With `[experimental.pgdelta] enabled = true`, they point to `permdock supabase hook generate --out <schema file>` without `--grants-out`, then `supabase db schema declarative sync`, instead of a grants migration. A hook whose grants are in the declarative schema file that defines it now counts as granted under pg-delta, and the finding for a file that already grants the hook names `supabase db schema declarative sync` before `supabase migration up`.

- [#22](https://github.com/ScaleDockHQ/better-supabase/pull/22) [`f8be1be`](https://github.com/ScaleDockHQ/better-supabase/commit/f8be1be21e0d860d241f6f87915b8ebc378381e1) Thanks [@martijn00](https://github.com/martijn00)! - Doctor BS408 checks exactly the PermDock helpers the `entitlements` module calls for the chosen scope, and no longer claims PermDock writes `member_<scope>_ids_for` for every scope. It warns when the manifest lacks `member_<scope>_ids` or doesn't let `authenticated` execute it, when it lacks `member_<scope>_ids_for` (add a membership source for the scope in `permdock.config.ts`), and when `supabase_auth_admin` may not execute `member_<scope>_ids_for` (add `supabase.hook.claims: { features: 'better_supabase.feature_claims' }`).

- [#22](https://github.com/ScaleDockHQ/better-supabase/pull/22) [`f8be1be`](https://github.com/ScaleDockHQ/better-supabase/commit/f8be1be21e0d860d241f6f87915b8ebc378381e1) Thanks [@martijn00](https://github.com/martijn00)! - The PermDock MCP recipe in the docs and the auth skill fails closed: a tool without a PermDock permission in `meta` is hidden (`visible` returns `false`) and refused (`authorize` returns `{ allowed: false }`). The page also shows PermDock's `decide` for putting the denial reason in the refusal.

- [#22](https://github.com/ScaleDockHQ/better-supabase/pull/22) [`f8be1be`](https://github.com/ScaleDockHQ/better-supabase/commit/f8be1be21e0d860d241f6f87915b8ebc378381e1) Thanks [@martijn00](https://github.com/martijn00)! - The `entitlements` kit module takes its PermDock scope from the manifest. Without `entitlements.permdock.scope`, it now uses the manifest's root scope (the `rls.scopes` entry without `within`) instead of `organization`, so a PermDock project whose root scope is `tenant` works without config. A manifest with no root scope or several stops `sql add entitlements` and doctor BS408 asks for `entitlements.permdock: { scope }`. An explicit `scope` still overrides, `false` still opts out, and a scope the manifest doesn't list is still reported by BS408. `permdockKeyStatus` and the `PermdockCatalog` and `PermdockKeyStatus` types are exported from `better-supabase/sql`.

- [#22](https://github.com/ScaleDockHQ/better-supabase/pull/22) [`f8be1be`](https://github.com/ScaleDockHQ/better-supabase/commit/f8be1be21e0d860d241f6f87915b8ebc378381e1) Thanks [@martijn00](https://github.com/martijn00)! - In PermDock mode, the `entitlements` kit module renders the tenant argument of `has_entitlement`, `tenant_entitlements` and `tenant_stripe_customer`, and the rows of `stripe_customer_tenants`, with the scope's id type from the manifest's `rls.scopes` (`uuid`, `text` or `bigint`) instead of always `uuid`. A missing or other type stops `sql add entitlements` and doctor BS408 reports it. `better-supabase/sql` exports `KIT_ID_TYPES`, `isKitIdType` and the `KitIdType` type, and `KitPermdock` has a required `idType`.

- [#22](https://github.com/ScaleDockHQ/better-supabase/pull/22) [`f8be1be`](https://github.com/ScaleDockHQ/better-supabase/commit/f8be1be21e0d860d241f6f87915b8ebc378381e1) Thanks [@martijn00](https://github.com/martijn00)! - The auth skill's PermDock caching recipe works as written. It passes only static tags to `bs.cached()`, then calls `cacheTag(snapshotTag(session.user.id))` and `cacheLife(cacheLifeFor(snapshot))` inside the loader once the snapshot is built, because the user id and the snapshot don't exist before `bs.cached()` returns. It pairs the recipe with `bs.invalidateSession(userId, { tags: [snapshotTag(userId)] })`.

- [#22](https://github.com/ScaleDockHQ/better-supabase/pull/22) [`f8be1be`](https://github.com/ScaleDockHQ/better-supabase/commit/f8be1be21e0d860d241f6f87915b8ebc378381e1) Thanks [@martijn00](https://github.com/martijn00)! - PermDock's catalog is read fail closed. `defineBucket` and `defineTopic` with `catalog` accept only keys marked `rowConditions: false`: a key whose entry has no boolean `rowConditions`, or that the catalog doesn't list, now throws with a message to regenerate the catalog with a current `permdock catalog`. Doctor BS214 reports those keys as errors, and `better-supabase gen` refuses to write their bucket policies.

## 0.4.0

### Minor Changes

- [#16](https://github.com/ScaleDockHQ/better-supabase/pull/16) [`aacef1c`](https://github.com/ScaleDockHQ/better-supabase/commit/aacef1c70c0b122f30e6641b96645720c159bb56) Thanks [@martijn00](https://github.com/martijn00)! - The CLI ships inside `better-supabase` again. Installing `better-supabase` gives you the `better-supabase` command, so drop `@better-supabase/cli` from your dev dependencies (it was never published) and run `npx better-supabase init` in a new project. The commands and their options are unchanged. The CLI's own dependencies are bundled into the package, so apps install nothing extra; `pg` stays an optional peer that the CLI needs to read your database.
  
  Import `run`, `registerCommand`, `defineCliCommand` and the introspection helpers from `better-supabase/cli`. `@supabase/config` is an optional peer again, for reading `supabase/config.toml`.
  
  `VERSION`, `better-supabase --version`, doctor reports and the header of newly written SQL kit files now show the package version instead of `0.0.0`. Existing kit files are not reported as changed, because the comparison ignores that version.

- [#18](https://github.com/ScaleDockHQ/better-supabase/pull/18) [`345a0b9`](https://github.com/ScaleDockHQ/better-supabase/commit/345a0b95136022a563ff42b7696b7a1914959473) Thanks [@martijn00](https://github.com/martijn00)! - Names are now the same in every adapter. The definition from `defineSupabase` is `betterSupabase`, and every runtime instance an adapter creates is `bs`. They live in `lib/supabase/index.ts`, `lib/supabase/server.ts` (with `import "server-only"` in Next.js) and `lib/supabase/client.ts`, which is what `better-supabase init` now writes. The old names have no aliases; the compiler points out each one. [Naming](https://bettersupabase.com/docs/concepts/naming) lists the conventions.
  
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

- [#20](https://github.com/ScaleDockHQ/better-supabase/pull/20) [`6948fc9`](https://github.com/ScaleDockHQ/better-supabase/commit/6948fc9c5f973a5d78fb9676079fa51323a3bbfd) Thanks [@martijn00](https://github.com/martijn00)! - Less work per request in auth and the adapters.
  
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

- [#20](https://github.com/ScaleDockHQ/better-supabase/pull/20) [`8b41284`](https://github.com/ScaleDockHQ/better-supabase/commit/8b4128490f52deaf5ccbf91bf815c13891826bfc) Thanks [@martijn00](https://github.com/martijn00)! - A faster CLI that reads the database less often.
  
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

- [#20](https://github.com/ScaleDockHQ/better-supabase/pull/20) [`5ce1b5b`](https://github.com/ScaleDockHQ/better-supabase/commit/5ce1b5b562e9fee9c7fc73eeae0f6a4bb03cb0e7) Thanks [@martijn00](https://github.com/martijn00)! - Fixes four bugs the performance audit found, one of which changes behavior.
  
  - `findMany` without `orderBy` now orders by the primary key's database names. On a camel-cased table whose key isn't `id` (`customerTags` with `customerId` and `tagId`) it sent `order=customerId.asc`, which PostgREST rejects.
  - `topic.send()` no longer closes a subscription on the same topic. realtime-js reuses the open channel for a topic, and `send()` removed it after sending.
  - `liveQuery` keeps the shared channel when a listener re-joins in the same tick (React StrictMode remounts), instead of subscribing the new listener to a closing channel.
  - A session refresh now times out after `refreshTimeoutMs` (5000 by default, an option of `resolveAuth` and every adapter's `auth`) and counts as a network failure. Before, a hung Auth request blocked every later request carrying the same refresh token. A rejected refresh is reused for ten seconds, like a successful one.
  
  Breaking: where refreshing is off (Server Components, route handlers, prefetches, MCP), a token in its last 60 seconds is now valid until its `exp`. It used to resolve as `{ kind: 'anon', reason: 'expired' }`, so pages rendered signed out in the last minute of every token. `leeway` now only decides when the proxy refreshes.

- [#20](https://github.com/ScaleDockHQ/better-supabase/pull/20) [`511c97b`](https://github.com/ScaleDockHQ/better-supabase/commit/511c97b9ab8b951fcc84031413dea51306a9921f) Thanks [@martijn00](https://github.com/martijn00)! - Generated files and types that cost less to check and to bundle.
  
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

- [#20](https://github.com/ScaleDockHQ/better-supabase/pull/20) [`36635e2`](https://github.com/ScaleDockHQ/better-supabase/commit/36635e2806618d6e07c7b7d7c6324cee9d89a4d7) Thanks [@martijn00](https://github.com/martijn00)! - Faster request path in the core runtime.
  
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

### Patch Changes

- [#16](https://github.com/ScaleDockHQ/better-supabase/pull/16) [`aacef1c`](https://github.com/ScaleDockHQ/better-supabase/commit/aacef1c70c0b122f30e6641b96645720c159bb56) Thanks [@martijn00](https://github.com/martijn00)! - The Agent Skills cover 0.3. A new `better-supabase-auth` skill teaches sessions, typed claims, OAuth clients and agents behind a token (`session.actor`, `session.delegation` and the `scopes` guard option), `checkSession` before irreversible actions, what happens when claims change, and how to run next to PermDock. The `better-supabase` skill adds an upgrade workflow, cursor pagination, `Temporal` values, the CLI's `--json`, `--db-url-stdin` and exit codes, and `member_org_ids()` in tenant policies. The `better-supabase-api` skill adds `scopes`, cursor resources, the MCP `authorize`, `visible` and `allowedHosts` options, the kit's purge functions and the Postgres pool options. The `better-supabase-testing` skill adds delegated-token API tests, `Temporal` in tests and doctor in CI. Run `better-supabase skills install` to update installed skills.

## 0.3.0

### Minor Changes

- [`c565c21`](https://github.com/ScaleDockHQ/better-supabase/commit/c565c21589f69a1d90110cb5480cf8b9256f7539) Thanks [@martijn00](https://github.com/martijn00)! - Name the OAuth client or agent behind a bearer token. A user session now carries `actor` and `delegation`, read from `client_id`, `scope` and the RFC 8693 `act` chain the way PermDock's `actorOf` and `delegationOf` read them. A malformed `act` chain resolves to `{ kind: 'invalid', reason: 'actor' }` and a 401, so `InvalidReason` gains `'actor'`: an exhaustive `switch` over it needs the new case. The `scopes` guard option on `next.route`, `next.action` and the edge, Hono and oRPC adapters answers 403 with an RFC 6750 `insufficient_scope` challenge when a delegated token lacks a scope; the user's own token is not limited. `forbidden` errors and Problem Details carry the needed `scopes`. `better-supabase/server` now exports `toSession`, `AuthSession`, `ActClaim`, `SessionActor` and `SessionDelegation`. A new monorepo guide shows one runtime package that owns `defineSupabase`, with domain packages typed from its `db`.

- [#13](https://github.com/ScaleDockHQ/better-supabase/pull/13) [`f9382a0`](https://github.com/ScaleDockHQ/better-supabase/commit/f9382a0ce67f6ee1a9b94fb505f35f704d2a711e) Thanks [@martijn00](https://github.com/martijn00)! - Breaking: the `BetterResultShape` type is now `BetterResultValue`. It is still the type `toBetterResult` returns, with the `status`, `value` and `error` fields of a better-result value; rename the import to upgrade.

- [#13](https://github.com/ScaleDockHQ/better-supabase/pull/13) [`f9382a0`](https://github.com/ScaleDockHQ/better-supabase/commit/f9382a0ce67f6ee1a9b94fb505f35f704d2a711e) Thanks [@martijn00](https://github.com/martijn00)! - On the Postgres executor, `createMany` and `upsertMany` split an insert that needs more than 65,535 bind parameters into several statements and run them in one transaction, instead of failing. `upsertMany` sends rows sorted by the conflict columns, so concurrent upserts over overlapping rows lock them in the same order instead of deadlocking; its returned rows follow that order.

- [#13](https://github.com/ScaleDockHQ/better-supabase/pull/13) [`f9382a0`](https://github.com/ScaleDockHQ/better-supabase/commit/f9382a0ce67f6ee1a9b94fb505f35f704d2a711e) Thanks [@martijn00](https://github.com/martijn00)! - `checkSession(sql, auth)` from `better-supabase/auth` and `better-supabase/server` confirms that a user token's session still exists in `auth.sessions`, and returns an `unauthorized` error with code `SESSION_REVOKED` when the user signed out or the session was ended. Call it before actions you can't undo, such as deleting the account. Nothing calls it by default, so other requests still verify tokens without a round trip.

- [`a68e785`](https://github.com/ScaleDockHQ/better-supabase/commit/a68e785606cc4d841e488bb360472a2d318c3f33) Thanks [@martijn00](https://github.com/martijn00)! - The CLI moved to its own package, `@better-supabase/cli`, released at the same version as `better-supabase`. Install it with `pnpm add -D @better-supabase/cli`; the `better-supabase` command and its options are unchanged.
  
  Breaking for `better-supabase`: the package no longer ships the `better-supabase` bin or the `better-supabase/cli` subpath. Import `run`, `registerCommand` and the introspection helpers from `@better-supabase/cli` instead. The new `better-supabase/sql` subpath exports the SQL kit (`renderKit`, `kitLayout`, `compileReadSets`), and `better-supabase/config` now exports the snapshot types, `DEFAULT_CLAIMS` and `tenantClaimPaths`.
  
  The library no longer has `@supabase/config` as an optional peer; only the CLI reads `supabase/config.toml`.

- [`02dc140`](https://github.com/ScaleDockHQ/better-supabase/commit/02dc140cb2f80d8b9fb3298ea48676259686277e) Thanks [@martijn00](https://github.com/martijn00)! - Doctor BS213 warns when `anon` or `authenticated` may insert or update a column that RLS helpers read to decide access, such as `memberships.role` or `contacts.customer_id`, and a policy lets them write the row. It also checks the `decidingColumns` in PermDock's manifest and names PD028. The finding lists the revoke and the grant of the remaining columns. Snapshots now record column-level insert and update grants (`columnGrants`); older snapshots only show table grants.

- [#13](https://github.com/ScaleDockHQ/better-supabase/pull/13) [`f9382a0`](https://github.com/ScaleDockHQ/better-supabase/commit/f9382a0ce67f6ee1a9b94fb505f35f704d2a711e) Thanks [@martijn00](https://github.com/martijn00)! - Doctor treats `security definer` functions and functions with a `set` option as not inlinable (BS205, BS206), and its advice for them now points to `column in (select helper())`. New checks: `auth.role()` (BS109), update policies without a select policy or `with check` (BS110), needless and unused API grants (BS111), exposed security definer functions that never check the caller (BS112), storage inserts without the upsert policies (BS113), helpers that read `user_metadata` (BS114), zero-argument helpers called without `select` (BS215), foreign keys without an index (BS216, replacing splinter's lint for the same table), tenant foreign keys that can cross tenants (BS217), soft-delete tables without a partial index (BS218), containment filters without GIN (BS219), column types to avoid (BS220) and direct connections in serverless apps (BS221). BS211 also reports `idle_in_transaction_session_timeout`.
  
  Snapshots now record each index's access method and predicate, and who among `anon` and `authenticated` may execute the functions doctor reads. Both fields are optional in `snapshot-v2.json`, so older snapshots still load.

- [`6834741`](https://github.com/ScaleDockHQ/better-supabase/commit/6834741edbfc324267449218e91220d89e2cdb47) Thanks [@martijn00](https://github.com/martijn00)! - The `entitlements` SQL kit module reads memberships from PermDock when `permdock.manifest.json` is present: `has_entitlement` checks `<rls.schema>.member_<scope>_ids()`, `feature_claims` reads `member_<scope>_ids_for(user_id)` from PermDock's hook, and `entitlement_members` reads the manifest's membership tables. `sql add entitlements` then no longer adds the `tenant` module or prints the hook note. The scope defaults to `organization`; set `entitlements.permdock: { scope }` for another of the manifest's scopes, or `entitlements.permdock: false` to keep `better_supabase.memberships`. The new doctor check BS408 warns when the manifest or the database lacks one of the two helpers.

- [#13](https://github.com/ScaleDockHQ/better-supabase/pull/13) [`f9382a0`](https://github.com/ScaleDockHQ/better-supabase/commit/f9382a0ce67f6ee1a9b94fb505f35f704d2a711e) Thanks [@martijn00](https://github.com/martijn00)! - Cursor pagination no longer skips rows whose sort column is null: the next page follows where Postgres places nulls (last for `asc`, first for `desc`, or the `nulls` option). On the `better-supabase/postgres` executor a cursor over columns that sort the same way and are not nullable compiles to a row comparison such as `(name, id) > ($1, $2)`, which one index range scan can serve.
  
  `defineListQuery`, `defineResource`, `createOpenApi` and the MCP table tools accept `pagination: "cursor"`. The list then takes `after` instead of `page`, returns `nextCursor` and `hasMore`, keeps `size` capped by `maxPageSize`, and documents the cursor in its OpenAPI parameters and JSON Schema. `paginate` and offset lists work as before.

- [#13](https://github.com/ScaleDockHQ/better-supabase/pull/13) [`f9382a0`](https://github.com/ScaleDockHQ/better-supabase/commit/f9382a0ce67f6ee1a9b94fb505f35f704d2a711e) Thanks [@martijn00](https://github.com/martijn00)! - The `audit`, `webhook-inbox` and `jobs` SQL kit modules add `purge_audit_log`, `purge_webhooks` and `purge_job_archive`. Each deletes rows older than an interval in batches and returns how many it deleted, for nightly pg_cron jobs. Only `service_role` can execute them. Run `better-supabase sql add` again to update the kit files.

- [#13](https://github.com/ScaleDockHQ/better-supabase/pull/13) [`f9382a0`](https://github.com/ScaleDockHQ/better-supabase/commit/f9382a0ce67f6ee1a9b94fb505f35f704d2a711e) Thanks [@martijn00](https://github.com/martijn00)! - Security fixes in the SQL kit. Rerun `better-supabase sql add` for the modules you installed to apply them:
  
  - `create_invitation` no longer lets an admin invite someone as `owner`; only an owner or the service role can. The service-role check reads `auth.jwt() ->> 'role'` instead of the deprecated `auth.role()`, and `invitations.role` gets the same check constraint as `memberships.role`.
  - `accept_invitation` requires the signed-in user's address in `auth.users` to be confirmed, not only an `email` claim. An unconfirmed user gets the hint `INVITATION_EMAIL_UNCONFIRMED`.
  - `anon` can no longer call `has_org_role`, and the pgTAP kit's `tests.create_user` is granted to `authenticated` and `service_role` only.
  - The tenant module adds `member_org_ids(roles)`, a set-returning helper. Write policies as `org_id in (select better_supabase.member_org_ids())`, which Postgres evaluates once per statement instead of once per row.
  - Deduplicated jobs get a partial index on `dedupe_key` in each queue table, so `enqueue_job` no longer scans the queue while it holds the advisory lock.
  - `triggerSql` puts the realtime trigger function in the `better_supabase` schema, which the Data API does not expose, instead of `public`.
  
  `better-supabase gen` names a composite foreign key that repeats a column on both sides, such as `(customer_id, organization_id)` referencing `(id, organization_id)`, after the remaining column: the relation is `customer`, as it would be for a plain `customer_id` key. Schemas with such keys get new relation names; set `tables.<name>.relations` to keep the old ones.

- [#13](https://github.com/ScaleDockHQ/better-supabase/pull/13) [`f9382a0`](https://github.com/ScaleDockHQ/better-supabase/commit/f9382a0ce67f6ee1a9b94fb505f35f704d2a711e) Thanks [@martijn00](https://github.com/martijn00)! - `createMcp` takes `allowedHosts`, which rejects requests whose `Host` header names another host (DNS rebinding protection, next to `allowedOrigins`), and `resourceDocumentation`, published as RFC 9728 `resource_documentation` in the protected resource metadata.

- [`809ab3d`](https://github.com/ScaleDockHQ/better-supabase/commit/809ab3df153a8b762dc8dc5b8d955f91fe6d3b84) Thanks [@martijn00](https://github.com/martijn00)! - `next.cached()` takes `tags` and `life.stale`. `tags` adds cache tags to the entry next to `bs:session:<user id>`, and `life.stale` caps the stale time `sessionStale` computes, so `next.cached({ tags: [snapshotTag(sub)], life: cacheLifeFor(snapshot) })` caches a PermDock snapshot no longer than the token or the snapshot. `next.invalidateSession(userId, { tags })` also expires the extra tags. PermDock can now drop the "Planned in better-supabase" note in its `guides/next-cache-components.mdx`.

- [`00fe466`](https://github.com/ScaleDockHQ/better-supabase/commit/00fe466752fa8c60cf48358c72603d4a63928036) Thanks [@martijn00](https://github.com/martijn00)! - Doctor and `gen` read PermDock's `permdock.manifest.json` and `permissions.catalog.json` (paths set by `permdock.manifest` and `permdock.catalog` in the config). BS407 recognizes PermDock's hook by the manifest or its `-- permdock:hook v1` marker, treats functions in `supabase.hook.claims` as the hook's own sources, flags a wrapper that writes those claims again, and reports an info finding when `permdock.config.ts` has no manifest. BS405 takes PermDock's budget from the manifest. The new BS214 reports bucket and topic policies that pass a permission with `rowConditions: true` to PermDock's helpers, `gen` refuses to write such bucket policies, and `defineBucket` and `defineTopic` throw for those keys when given the catalog as `catalog`. The MCP recipe narrows `tool.meta` with PermDock's `isPermission` before `can` and `mayUse`.

- [#13](https://github.com/ScaleDockHQ/better-supabase/pull/13) [`f9382a0`](https://github.com/ScaleDockHQ/better-supabase/commit/f9382a0ce67f6ee1a9b94fb505f35f704d2a711e) Thanks [@martijn00](https://github.com/martijn00)! - `createPostgres` applies Supabase's role timeouts per transaction: `statement_timeout` 8 s for `asUser` and 3 s for `anon`, because `set role` skips the role's own setting. `statementTimeout` takes a number for every role or one value per role (`admin`, `authenticated`, `anon`). New options: `idleInTransactionTimeout`, `connectionTimeout` and `idleTimeout` (both default to 10 s). Each transaction now sets its timeouts, claims and role in one query after `begin`.

- [`0c4db9e`](https://github.com/ScaleDockHQ/better-supabase/commit/0c4db9e3c0bcd11af17ea2349ab14354f0766250) Thanks [@martijn00](https://github.com/martijn00)! - `createPostgres({ pool })` runs on an existing `pg.Pool` or any object with `connect()` and `end()`, typed as the new `PgPool` and `PgPoolClient` exports of `better-supabase/postgres`. `list.parse()` now reads a typed `ListQueryInput` such as `{ page: 2, size: 10 }` instead of treating it as URL search params and falling back to page 1, and a non-string `q` such as `{ q: 5 }` reports `Must be text` instead of being accepted. `contextFromSupabase` throws a `TypeError` for an auth mode it does not know instead of returning it as the request context. The standards page lists the conformance test behind each adopted standard.

- [`8d68216`](https://github.com/ScaleDockHQ/better-supabase/commit/8d68216d44962ca93ae2a980b2a284839887934e) Thanks [@martijn00](https://github.com/martijn00)! - Doctor reads the declarative schemas in `[db.migrations] schema_paths` order, then the files no entry matches, then the migrations newest first, and the built-in `config.toml` parser reads arrays over several lines. `sql add` names the kit files no `schema_paths` entry matches, because `supabase db diff` would skip them. `doctor --fix-grants` prints the grant and revoke SQL BS404 asks for as one block to append to the migration `supabase db diff` wrote. For PermDock's hook, BS404 points to `permdock supabase hook generate --grants-out` instead, and when a `-- permdock:grants v1` migration already grants the function, it says to apply the migrations.

- [#13](https://github.com/ScaleDockHQ/better-supabase/pull/13) [`f9382a0`](https://github.com/ScaleDockHQ/better-supabase/commit/f9382a0ce67f6ee1a9b94fb505f35f704d2a711e) Thanks [@martijn00](https://github.com/martijn00)! - Breaking: time values in the public API are now `Temporal` values instead of `Date` objects and epoch numbers.
  
  - The `codecs.timestamptz` option takes `'instant'` instead of `'date'`. `timestamptz` columns decode to `Temporal.Instant`, `timestamp` columns to `Temporal.PlainDateTime`, and both keep microseconds. Rename the option and run `better-supabase gen`.
  - The `now` options of `defineSupabase`, plugin hooks, `toCloudEvents`, `forwardMutations`, `verifyWebhook` and `bucket.sweep` return a `Temporal.Instant`.
  - `Job.enqueuedAt`, `Job.visibleUntil`, `InboxMessage.receivedAt`, `EnqueueOptions.runAt`, the verified webhook `timestamp` and the `signWebhook` `timestamp` are `Temporal.Instant`.
  - `bucket.sweep({ olderThan })` takes a `Temporal.Duration` or a `Temporal.Instant` instead of milliseconds.
  - TypeScript 5.9 is no longer supported, because it has no Temporal lib. Use TypeScript 6 or 7.
  
  On Node 24, Safari and other runtimes without a native `Temporal`, install `temporal-polyfill` and import `temporal-polyfill/global` once at startup. Without it, the calls that need `Temporal` return a `DbError` that names the import. Auth keeps its `now` option in epoch milliseconds.

### Patch Changes

- [`24cc853`](https://github.com/ScaleDockHQ/better-supabase/commit/24cc8531eaebfc521d6329bd01aadd8b8d67291a) Thanks [@martijn00](https://github.com/martijn00)! - The PermDock docs and the plugins skill reference match current PermDock. With `supabase.hook.claims: { features: 'better_supabase.feature_claims' }` in `permdock.config.ts`, PermDock's hook writes the `features` claim, so `hasEntitlement(session, ...)` works next to PermDock. The MCP recipe answers `visible` with PermDock's `mayUse`, and the Storage and Realtime pages point to the catalog's `rowConditions` and `permdock doctor` PD037 for permissions the helpers don't fully check.

- [#13](https://github.com/ScaleDockHQ/better-supabase/pull/13) [`f9382a0`](https://github.com/ScaleDockHQ/better-supabase/commit/f9382a0ce67f6ee1a9b94fb505f35f704d2a711e) Thanks [@martijn00](https://github.com/martijn00)! - Two public types no longer rely on DOM-only globals. The `headers` option of `problem()` takes what the global `Headers` constructor accepts, and the JSON Web Keys in `better-supabase/testing` use the `node:crypto` type, so both resolve in a project whose `lib` leaves out `"DOM"`.

- [#13](https://github.com/ScaleDockHQ/better-supabase/pull/13) [`f9382a0`](https://github.com/ScaleDockHQ/better-supabase/commit/f9382a0ce67f6ee1a9b94fb505f35f704d2a711e) Thanks [@martijn00](https://github.com/martijn00)! - The `better-supabase` skill's schema workflow now asks for RLS, policies, policy indexes and Data API grants on every new table, and points to Supabase's own skills. The CLI asks for an access token scoped to the project when it reads a hosted project.

- [#13](https://github.com/ScaleDockHQ/better-supabase/pull/13) [`f9382a0`](https://github.com/ScaleDockHQ/better-supabase/commit/f9382a0ce67f6ee1a9b94fb505f35f704d2a711e) Thanks [@martijn00](https://github.com/martijn00)! - `better-supabase gen` uses `@supabase/postgrest-typegen` 0.3.1, which still produces the same `database.types.ts` as `supabase gen types` from Supabase CLI 2.119. Version 0.4.0 adds a `ComputedFields` key that the Supabase CLI does not emit yet, so it waits until the CLI catches up. The optional `@supabase/config` peer now accepts 0.11.

## 0.2.0

### Minor Changes

- 11f592c: `createMcp` takes optional per-tool authorization hooks. `authorize(ctx, tool, args)` runs after the arguments are validated and before `run`, and returns `{ allowed: true }` or `{ allowed: false, reason?, scopes? }`. A refusal is a tool error, and a refusal with `scopes` is a 403 `insufficient_scope` challenge that lists the scopes the call needs. `visible(ctx, tool)` filters `tools/list`, and a hidden tool is called like an unknown one. `defineTool` and `mcp.tool` accept an opaque `meta`, for example a PermDock permission, which both hooks receive and clients never see. New types: `ToolRef` and `ToolDecision`. The PermDock guide has a recipe that checks PermDock permissions through a structural type.
- 3c0e11d: Align with PermDock's authorization contract, so a project can use better-supabase and PermDock on the same claims. The migration guide at https://bettersupabase.com/docs/migration/0.1-to-0.2 lists every step.
  
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

### Patch Changes

- e774925: Doctor BS405 now measures what PermDock's budget covers. With a `permdock.config.ts`, it warns when `memberships` plus `attrs` from the hook's output pass 1024 bytes (or `doctor.claimsLimit`), measured with `octet_length` as PermDock's hook measures `supabase.hook.budget`. The whole-token check at 2048 bytes is a separate warning, so a normal PermDock token of about 1.5 KB no longer trips it. Without PermDock, `doctor.claimsLimit` still limits the whole token. `memberships_truncated` is reported as before.
- 091c6b5: Entitlements are no longer treated as a PermDock conflict, because `features` is not a PermDock claim.
  
  - Doctor BS407 reports a custom access token hook next to PermDock only when it calls `better_supabase.membership_claims` or writes `roles`, `user_role`, `memberships` or the configured tenant claim itself. It no longer reports `feature_claims`, and it leaves PermDock's generated hook alone.
  - `sql add entitlements` works next to a `permdock.config.ts` without `--force`. It writes `tenant` as a dependency and prints a note. Only `sql add tenant` still needs `--force`.
  - The PermDock and entitlements docs say what works today. `has_entitlement(tenant, key)` and `tenant_entitlements(tenant)` work in SQL and RLS without a claim. `hasEntitlement(session, ...)` needs the `features` claim, which PermDock's hook doesn't write yet, so read entitlements from the database on the server until PermDock adds a hook slot for it.
- a0f0160: The PermDock guide lists every claim PermDock's generated hook writes (`user_role`, `roles`, `memberships`, the tenant claim, `attrs`, `authz_ver` and `memberships_truncated`). The migration guide and the `sb.userMetadata()` TSDoc say that `session.profile` is for display only, and that roles, memberships, the tenant and entitlements never come from it.
- 0c66c57: The storage and realtime docs say that the `permdock` policy mode compares ids as text, so a path or topic segment must be the id's canonical lowercase form: an uppercase uuid is denied. An integration test covers it for buckets and topics.
- 8f3d0e5: The docs now name the right PermDock command for the SQL helpers. `permdock_has` and `permitted_<scope>_ids` come from `permdock rls generate`, not from `permdock supabase hook generate`. The PermDock guide gains a setup step that runs both commands, and says that the helpers live in PermDock's `rls.schema`, which must equal the `schema` option on buckets and topics.
- 50b4ac6: Document that the `permdock` policy mode for buckets and topics only fits permissions whose grants have no row conditions beyond the scope. PermDock's helpers check role and scope, so a permission with row conditions (for example `ownerId = principal.id`) would grant every object in the scope. Leave those to the policies `permdock rls generate` writes. The storage, realtime and PermDock docs pages show a wrong and a right example, and the TSDoc on the `policy` and `permdock` options says the same.
- edc6b57: The PermDock guide says that a non-default `claims.tenant` must also be set as PermDock's `rls.tenantClaim` and passed to `subjectFromSupabase` or `subjectFromSupabaseSession` as `{ tenant }`, so both packages read and write the same tenant claim.

## 0.1.0

### Minor Changes

- 6feda1d: Aggregates in one request. `include: { _sum | _avg | _min | _max: { relation: { column: true } } }`
  aggregates related rows next to each parent row, and `db.x.aggregate({ where, groupBy, _count, _sum,
  ... })` returns totals or one row per group, over PostgREST and SQL, typed in the configured casing.
  `aggregate` is a spec and query-options method. PGRST123 (aggregates off) maps to `invalid_request`
  with a hint, doctor BS210 warns when the app uses aggregates while `pgrst.db_aggregates_enabled` is
  off (new `doctor.sources` option), and `SPEC_PINS.postgrestAggregates` pins the syntax.
- bb2838a: Typed, validated JWT claims. `sb.claims(schema)` takes any Standard Schema and returns a definition
  whose servers validate the verified claims on every request, including memoized tokens. The output
  is merged over the payload and types `ctx.auth.claims`, `next.session()`, `useSession` from
  `createHooks<typeof browser>()` and the new generic `useSession<C>()`. `tenant<C>({ claim })`
  accepts only dotted paths to string claims. A token whose claims fail resolves to
  `{ kind: 'invalid', reason: 'claims' }` (401, `CLAIMS_INVALID`) and is never refreshed. The
  `invalid` state now always has a `reason` (`'token'` or `'claims'`). `AuthResolver`s may leave it
  out, and it then counts as `'token'`.
- c379e2f: Add `sb.mapError(fn)`, so `.orThrow()` throws your own error while results keep their `DbError`. Add `toBetterResult(result, Result, mapError?)` and `fromBetterResult(r)` to convert to and from better-result values without depending on it. Errors whose `cause` is a `DbError` are now recognised by the server, Hono and oRPC adapters and by `isConflict`, `isCheck` and `isForeignKey`. TanStack Query hooks keep throwing `DbException`.
- a62eceb: Data API grants. Supabase no longer grants new tables to `anon` and
  `authenticated` (new projects since May 30, 2026, existing projects from
  October 30, 2026). Declare what each role reaches in the new `expose` config,
  write the grants with `better-supabase sql add grants`, and let doctor report
  missing grants as BS106 (it also notes `[api] auto_expose_new_tables = false`).
  `permission denied for table` errors are still `forbidden`, and their `hint`
  now points at `expose`.
- 28e8c49: Add `server.deleteAccount(userId, { buckets, cascades })`. It removes the
  user's objects from buckets with an owner placeholder (`bucket.owner`), deletes
  the Auth user, and emits `mutation` notices for `auth.users` and the tables in
  `cascades`; `next.deleteAccount` also invalidates the user's cached session. It
  returns a `Result` and never throws. Doctor reports foreign keys to
  `auth.users` without `on delete cascade` or `set null` as BS406.
- f645f12: Auth hook checks in `doctor`. Snapshots now record the functions behind every enabled
  `[auth.hook.*]` with a `pg-functions://` URI, in any schema, with their execute and schema-usage
  grants. BS404 (error) reports a hook function that doesn't exist, that `supabase_auth_admin` can't
  call, or that `authenticated`, `anon` or `public` can call, and lists the fixing SQL. BS405
  (warning) reports a custom access token hook that isn't `stable` or lacks `set search_path = ''`.
  With `--as <user id>`, BS405 also calls the hook for that user in a rolled-back transaction and
  warns when the claims it returns are over 2 KB.
- 0271503: RLS performance checks in `doctor`. Snapshots now record the functions each policy calls (from
  `pg_depend`) and those functions' language, volatility, security and `set` options. New checks:
  BS205 (a plpgsql or volatile helper called with a row column, so it runs per row), BS206 (a
  security definer helper in more than `doctor.policyHelperLimit` policies, default 5, that isn't
  `language sql stable`), BS207 (several permissive policies for one command and role; replaces
  splinter's `multiple_permissive_policies` for the same table), BS208 (temp-file spills from
  `pg_stat_database` with `work_mem` and the top statements), BS209 (`--stats`: statements over 50 ms
  mean with more than 1000 calls) and BS211 (role `statement_timeout` values and function timeouts
  PostgREST won't hoist). `doctor --explain <tables> [--as <uuid> | --claims <json>]` (BS212) runs
  `EXPLAIN (ANALYZE, BUFFERS)` under RLS in a rolled-back transaction and reports InitPlans, per-row
  SubPlans and each helper's share of the time, never row data. `--stats` and `--explain` read the
  live database even when the config names a saved snapshot.
- c115f6f: Add the `entitlements` SQL kit module over the Stripe Sync Engine
  (`SPEC_PINS.stripeSyncEngine`, 0.48.5): `tenant_entitlements()`,
  `has_entitlement()` for RLS, `membership_claims()` for the access token hook's
  `memberships[].entitlements`, and `entitlement_members()`. The Stripe customer
  column is set with the new `entitlements` config key. `hasEntitlement(session,
  tenantId, key)` is typed from `sb.claims()`, and `better-supabase/jobs` adds
  `ENTITLEMENTS_UPDATED` and `entitlementMembers()` for invalidating sessions
  after `entitlements.active_entitlement_summary.updated`.
- 71e168b: Audited impersonation: `server.actingAs(userId, claims, { actor, reason })` adds an RFC 8693 `act` claim, the `audit` SQL kit module records `impersonated_by` and `impersonation_reason`, and `track_actor(table, impersonated_by => 'column')` stamps the admin on each write. `session.impersonator`, `context.actor.impersonator` and `impersonatorOf(claims)` expose it for banners and plugins. Works over `better-supabase/postgres` only.
- 8290b9c: First release: generated schema, typed repository, plugins, auth and framework
  integrations, kits, opt-in standards and the `better-supabase` CLI.
- 971d414: List facet counts and count modes. `defineListQuery(sb, table, { facetCounts: true })` makes `run`
  return `page.facetCounts` (rows per facet value, where each facet applies the other facets'
  selections) from one grouped aggregate that runs in parallel with the page: 2 calls, 1 wave.
  `count: 'exact' | 'planned' | 'estimated'` can be set in the config or per `run`. `ListExtra.include`
  now takes the relation map (`{ notes: true, _count: { notes: true } }`) instead of a single
  relation's options. Doctor's BS210 also flags `facetCounts: true` when PostgREST aggregates are off.
- e4ebda2: Add live counts: `useLiveCount(spec | seed)` in `better-supabase/react`, `liveCount()` in `better-supabase/realtime` and `next.liveCount(spec)` for a server-rendered seed. They refetch only the count (a HEAD request) after changes. Live queries and live counts now also refetch once when their channel rejoins, because broadcasts sent while disconnected are lost.
- 17d9ed6: Add MFA assurance levels. User sessions expose `aal` and `amr`; route, action,
  Hono, oRPC, edge and MCP guards take `aal: 'aal2'` and answer `403` with
  `code: 'INSUFFICIENT_AAL'` and `required`; `requireAal` redirects pages in the
  proxy; `checkAal`, `aalOf` and `amrOf` are exported from `better-supabase/server`.
  The new `mfa` SQL kit module adds `better_supabase.mfa_satisfied()` for
  restrictive policies, and doctor reports policies that read `auth.mfa_factors`
  directly as BS108.
- be705ed: Cheaper private-cache scopes in Next.js. Verified access tokens are remembered until they expire, so
  twelve islands check the signature once, and `db`, `supabase` and `sql` on a server context are built
  on first use. New: `next.cached()` (session-aware `cacheLife` plus a `bs:session:<id>` tag),
  `next.invalidateSession(userId)`, `next.serverFor(session, { token })`, `server.contextFor(auth)` and
  `sessionStale(session)`.
- 16dc910: Next.js Cache Components support. `next.session()` returns the verified caller
  as serializable data (no token, no clients), ready to wrap in a
  `'use cache: private'` function. `SessionProvider` and `useSession()` in
  `better-supabase/react` share that session promise with Client Components, and
  the `react-server` build renders `SessionProvider` as a client reference so a
  Server Component layout can pass the promise inside `<Suspense>`. `toSession()`
  and the `AuthSession` type are exported from `better-supabase/next` and
  `better-supabase/ssr`.
- 8290b9c: Generate types with `@supabase/postgrest-typegen` and build caching, live
  queries and safety checks on the metadata it provides.
  
  **Breaking changes**
  
  - `gen` needs a database: a local connection, or the Management API for a
    project ref (`--project-ref`, `SUPABASE_ACCESS_TOKEN`). `database.types.ts`
    is now the `supabase gen types` output. The `types` config option is
    removed, and snapshots are version 2 (regenerate them).
  - Doctor: BS101, BS102, BS104, BS105, BS201, BS202 and BS203 are retired.
    Supabase's advisors report those problems now, as BS100 (security) and
    BS200 (performance), through the Management API or a pinned, hash-checked
    splinter run locally.
  - Jobs run on pgmq and pg_cron. Re-run `better-supabase sql add jobs`.
    `createJobs(source, queues)` no longer takes `worker`; `delay`, `lease`
    and `retryIn` are seconds; `Job` has `enqueuedAt`, `visibleUntil` and
    `lastError`. Over PostgREST, jobs use `pgmq_public` (no dedupe, schedules
    or lease extension).
  - `/query` is built on `@tanstack/query-core` and invalidates by the tables
    a query read (`meta.bsTables`) instead of by key prefix.
  - Writing a generated, identity or read-only view column fails with
    `invalid_request` before the request.
  
  **New**
  
  - `findUnique` by any unique key, typed constraint names and `isConflict`,
    `isCheck`, `isForeignKey`; `orThrow(factory)`; `codecs` config.
  - Serializable query specs (`sb.spec`, `db.$run`, `InferResult`), cascade-aware
    invalidation, `sb.defineRpc(name, { invalidates })`, `next.cacheTags(spec)`.
  - `skipToken`, offset infinite queries, `$rpc`, `$rpcMutation`, `$prefetch`.
  - Live queries: `liveQuery`, `useLiveQuery` and the `realtime-tables` SQL
    module; doctor BS305 and BS306.
  - `_count` includes, `db.$table(name)`, `db.$withoutPlugins()`.
  - `better-supabase/plugins/rules` (runtime query rules with presets) and
    `better-supabase/lint` (ESLint and oxlint plugin); `sensitive` config.
  - `jsonb-schemas` SQL module (pg_jsonschema check constraints from Standard
    JSON Schema); `supabase/config.toml` read through `@supabase/config` when
    installed.
- c774d30: `next.proxy()` composes with other middleware: `before(request)` runs next to the session check and may return a rewrite or redirect (next-intl), refreshed cookies and forwarded request headers are merged into it, and `after(response, auth)` post-processes the result. `serverTiming: true` adds a `Server-Timing` header (`bs-proxy`, `bs-verify`), pinned in `SPEC_PINS.serverTiming`. With a secret key, session refreshes send the client IP as `Sb-Forwarded-For` (`auth.clientIp`, exported `clientIp()`).
- f7df757: Write rate limits: the `rate-limit` SQL kit module adds `set_rate_limit(scope, max, period, key_claim)` and a `pgrst.db_pre_request` hook that counts Data API writes (POST, PATCH, PUT, DELETE) per user or claim and answers over-limit requests with 429 and `Retry-After`. The new `rate_limited` `DbError` kind (429) carries `retryAfter`, and `problemResponse()` sets the `Retry-After` header.
- 264032b: Read replicas: set `SUPABASE_READ_URL` (or `readUrl`) and the server sends each request's reads to the replica and its writes to the primary. A successful write pins the request to the primary, and Next.js actions and routes set a `bs-primary-until` cookie so the next requests read their own writes for `replicas.pinMs` (5 s). `ctx.replica.pin()` pins after raw `$client`/`$sql` writes. `sb.connect(client, { executor })` runs queries through a custom executor while keeping `$client`.
- d6f6ab4: Read sets and `db.$many`. `defineReadSet(sb, name, { params }, (s, p) => ({ ... }))` names several
  reads with typed placeholders; the `readSets` config key lets `gen` compile each set into a `stable`,
  `security invoker` function in the new `read-sets` SQL kit module (BS304 covers drift).
  `db.$many(readSet, params)` runs it as one GET over PostgREST and as one transaction over
  `better-supabase/postgres`; `db.$many([specA, specB])` returns a typed tuple, in one parallel wave or
  one transaction. `Executor` gains an optional `batch(ops)` (checked by `testExecutor`), `SqlClient`
  an optional `transaction`, and the rpc context a `get` flag. `next.cacheTags` accepts an array of
  specs or a read set.
- 5ae4526: Request budget. `db.$stats()` and `ctx.stats()` report calls, sequential
  waves, tables and time. `createNext(sb, { debug: { budget } })` gives every
  render a request id in the proxy, records every `next.server()` scope into
  it, warns in development when a render goes over budget, adds
  `x-bs-db-calls` to route handler responses and serves totals from
  `next.debugRoute()`. `expectDbBudget(page, ...)` in `better-supabase/testing`
  fails a Playwright test when a page gets chattier.
- 2245c8d: Row caps and deterministic order.
  
  - `defineSupabase(schema, { maxRows })` (default 1000, PostgREST's hosted `db-max-rows`). An unbounded read that returns `maxRows` rows sets `truncated: true` on the `query` event and logs a warning once per table; the result is unchanged.
  - **Behaviour change:** `findMany` without `orderBy` now orders by the primary key, so repeated reads return rows in the same order. Views and keyless tables are unchanged.
  - `gen` marks tables Postgres estimates at 10,000 rows or more with `large: true` in `supabase/snapshot.json`.
  - New lint rule `unbounded-read` with `largeTables(snapshot)`: flags `findMany` without `limit` on large tables, or on every table with `strict: true`.
- a6685f1: Storage paths and image URLs. `StoragePath<'bucket-id'>` brands paths from `bucket.path()` and `upload()`, and bucket clients reject paths of other buckets. The `storagePaths` config types text columns as `StoragePath` in generated rows (zod and valibot schemas follow). New `better-supabase/next/image` subpath: `createImageLoader({ url })` is a `next/image` `loaderFile` that serves public objects through Storage image transformations. New `storagePathColumns` query rule (in `recommended()` and `strict()`) flags Storage URLs and bucket paths written to `*_url` columns. `renderUrl` is covered against `/render/image/public` and `/render/image/sign`.
- 4c96e86: Tenant isolation testing.
  
  - `expectTenantIsolation(sb, { tenants, tables, stack?, seed? })` in `better-supabase/testing` seeds one row per tenant through the service role and asserts that a user of each tenant can't select, insert, update or delete the other's rows. It runs without plugins, checks each user can read its own row, and throws a `ConformanceError` naming every leaking table and command.
  - `LocalStack.secretKey` (defaults to `$SUPABASE_SECRET_KEY`).
  - Doctor BS107 (warning): a tenant-scoped table has policies for some commands but not all four.
- 445c837: Add vector search. The `vector-search` SQL kit module writes a security invoker `search_<table>(query, k)` function for each table in the new `vectorSearch` config key, using pgvector's iterative HNSW scans so RLS filters still return `k` rows. `db.$search(table, { vector, k, select, include, where })` reads through it with the usual selection, filters and casing. Executors opt in with `Executor.functionSources`, and read from the new `SelectOp.source`. `SPEC_PINS.pgvector` pins pgvector 0.8.

### Patch Changes

- 16dc910: Docs, problem `type` URIs, doctor `help` links and lint rule docs now point to
  `https://bettersupabase.com`.
- 10ed113: Document the four render stages of a Cache Components page and which `better-supabase/next` API belongs to each, and add CRM ports that pin the request budget of a faceted list, a badge read set and a `customer_id`-scoped portal.
- 291a0de: Agent skills are now task workflows with a "Done when" check for each, plus reference files:
  `references/plugins.md` and `references/troubleshooting.md` (every `DbError` kind and its usual
  cause) for `better-supabase`, and `references/adapters.md` for `better-supabase-api`.
  `better-supabase skills install` copies the reference files next to each `SKILL.md`, and `--check`
  compares them too. The skills help mentions `npx skills add ScaleDockHQ/better-supabase` for other
  agents, and the main skill points at the Markdown docs (`/docs/<path>.md`). The package now ships a
  README for npm.
- f645f12: Saved snapshots keep `functions` and `roleSettings` when doctor reads them, so the RLS checks
  (BS205 to BS207, BS210, BS211) see the same data as a live run.
- 291a0de: Updates `@supabase/server` to 1.8.1 and `@supabase/middleware` to 0.6.0. Tested against
  `@supabase/supabase-js` 2.117 and `@tanstack/query-core` 5.104; the peer ranges are unchanged.
