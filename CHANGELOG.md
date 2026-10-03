# Changelog

## 0.5.0 (2026-10-03)

- Guards refuse anonymous users (`signInAnonymously()`, the `is_anonymous` claim) with a 403 `ANONYMOUS_USER` unless `allow` lists `'anonymous'` or `'anon'`, `toSession()` adds `anonymous`, and the `realtime-tables` kit module sends anonymous users no change signals. Before 1.0 this minor release is the breaking slot: routes that served guest sessions need `allow: ['user', 'anonymous']`.

  The framework adapters agree with each other. `ctx.apply(response)` adds refreshed session cookies and, after a write, `bs-primary-until`, so Hono, edge and the new oRPC `bs.fetchHandler(handler)` keep read-your-writes like Next.js does. MCP reads the session from the `Authorization` header only, answers an unreachable JWKS with a 503 instead of a scope challenge, sends a missing second factor as a plain 403, takes `advertisedScopes` (with `scopes` as a deprecated alias) and enforces `requiredScopes`. REST resources refuse cross-site form posts that ride on the session cookie (`CROSS_SITE_REQUEST`) and answer malformed keys and bodies with `invalid_input`, whose detail survives in production. Hono's `bs.onError` returns an `HTTPException`'s own response, Next.js route handlers turn unexpected throws into a 500 Problem Details response while `redirect()` and `notFound()` still work, and `contextForSession` requires the token's auth kind to match the session. `createServer` takes `fetch` for its PostgREST and supabase-js clients, the `auth` event carries `reason` and `rawSource`, the `react-server` build exports `hasEntitlement` and `useLiveCount`, and every adapter builds the user actor, impersonator included, from one function.
- `better-supabase/hono` adds `bs.app()`, a `Hono` app typed with the adapter's `Env` and with `bs.onError` installed, and the type-only `bs.Env` for apps that build their own. After `@supabase/server`'s `withSupabase`, `bs.middleware()` reuses its verification of the bearer token when the stored claims are that token's payload, then runs its own claims, `act` and `userMetadata` checks.

  `clearOnUserChange(queryClient, auth)` in `better-supabase/query` removes the `["bs"]` queries when the signed-in user changes, for apps without React; `BetterSupabaseProvider` uses it.

  A bucket with `tenant` now checks paths on the client too: `upload`, `download`, signing, `remove`, `reserve` and `list` refuse a path in another tenant's segment, or any path when the connection has no tenant, with a `forbidden` error before calling Storage. Pass `{ context }` or `{ tenant }` to `connect()`, or `{ allTenants: true }` for cross-tenant admin work; `deleteAccount` does the latter. `client.path(target)` returns the checked path.

  Jobs record the enqueuing request's actor and tenant: `enqueue(queue, payload, { context })` and `schedule(..., { context })` store them next to the payload, and the handler gets them as `job.context`, ready for `db.$with(job.context)`. A job without a tenant gets the `tenant()` plugin's `onMissing` unless the worker runs with `allTenants: true`.

  `actor()` fills an `impersonatedBy` column (generated from `impersonated_by`, the column the SQL kit's `track_actor` stamps) from the impersonating admin, and clears it on writes without one.

  Event sink sends are tracked on `betterSupabase.events` (`pending`, `settled()`). Next.js routes and actions hand them to `after()`, and edge handlers to `waitUntil`: the Workers `ctx`, or `createEdge(..., { waitUntil })` on Supabase.

  The PermDock guide has oRPC and Hono recipes that refuse a procedure or route without a permission.
- The PermDock integration fails closed in more places. Buckets and topics in `permdock` mode now call PermDock's helpers in `permdock`, PermDock's default `rls.schema`, instead of `public`; set `schema: 'public'` on the policy if your PermDock config writes them there. `gen` and doctor BS214 refuse PermDock bucket policies when `permissions.catalog.json` is missing, and the catalog must be version 1. `sql add entitlements` refuses a PermDock project without a manifest or `rls` block instead of falling back to the tenant module (set `entitlements.permdock: false` for that). BS214 also reports a helper schema other than the manifest's, a scope the manifest doesn't declare and a key checked at another scope than its catalog entry. BS408 checks that PermDock's hook fills `claims.features` from `better_supabase.feature_claims` and that a membership source covers the scope. The new BS409 reports a `claims.tenant` that differs from the manifest's `rls.tenantClaim`, PermDock markers other than v1 and a `claims.scope` that isn't the root scope. Scope id types `integer`, `int8` and other aliases are accepted, and MCP table tools take a permission per operation from the resource's `meta`.
- Plugins compose without holes. `timestamps()`, `actor()` and `softDelete()` refuse caller-supplied values for the columns they fill unless the call passes `{ override: true }`, and generated JSON Schema and OpenAPI documents mark those columns `readOnly`. On tenant tables, an upsert that updates on conflict needs the tenant column in its conflict target, the SQL executor guards the update with `where <tenant> = excluded.<tenant>`, a query whose includes reach a tenant table fails closed without a tenant, and numeric tenant columns compare by their text. An upsert that updates a soft-deleted row restores it.

  `rules()` runs before every other plugin. `noUnboundedFindMany` skips aggregates, `maxLimit` ignores `paginate()`'s look-ahead row, `requireTenantContext` reads the same claim paths as `tenant()`, and `noSensitiveSelect` checks reads only, because writes without a `select` no longer return sensitive columns. Offset `paginate()` orders by the primary key by default. `validation()` decodes codec columns (Temporal values, `bigint`) before validating and encodes them afterwards.

  Mutation events give hooks and listeners a copy of the rows, so they can't change the result (`testPlugin` checks this), and carry `intent` (`softDelete` for a delete that became an update), the affected primary `keys` when they are known, and the `tenant` that `tenant()` resolved. CloudEvents and cache invalidation use them, so soft deletes send `row.softdeleted` events and invalidate their rows. `defineReadSet` warns when query plugins scope tables its generated function reads. The audit kit keys entries by each table's primary key and reads the tenant column from `plugins.tenant.column`, and `gen` refuses a soft-delete column that isn't a timestamp.
- Values from Postgres and the peer libraries no longer break responses. JSON responses from the server adapters and MCP write `bigint` values as decimal strings. A `timestamptz` or `timestamp` holding `infinity` comes back as an `invalid_value` error (status 500, with `column`) instead of throwing, because Temporal has no infinite value. Temporal values from another realm or a second polyfill copy are recognized by their `Symbol.toStringTag`, and Standard Schema issues with symbol path keys keep the error serializable.

  `loadEnv()` reads inline keys from `SUPABASE_JWKS`, as `@supabase/server` does, and verifies with them without fetching `jwksUrl`. The OpenTelemetry plugin writes `db.namespace` as `{database}|{schema}` (`postgres|public` by default, `otel({ database })` to change it), adds `server.address` and `server.port` from `otel({ server })` to spans and metrics, and sets `db.response.status_code` only for SQLSTATE codes. `BetterQueryMeta` builds on the app's `Register['queryMeta']`, and `send_email`'s `email_data` accepts fields Auth adds later.

  Doctor's BS410 reports HTTP auth hooks and checks their `v1,whsec_` secrets, and its custom access token hook event carries `iss` and `amr`. The peer ranges now state what the code needs: `pg >=8.15 <9`, `@tanstack/query-core ^5.62.0`, `@orpc/server >=2.0.0-beta.40 <3`, `hono <5`, `next <17`, `@opentelemetry/api <2`, and `oxfmt 0.66.0`, the version `@supabase/postgrest-typegen` pins; the `gen` notice and docs show how to allow a newer oxfmt.
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
