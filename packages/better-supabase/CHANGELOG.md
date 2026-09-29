# better-supabase

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
