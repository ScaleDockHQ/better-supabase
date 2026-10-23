# Core

Corrections for `packages/better-supabase/src/core`, the plugins and the block
extensions.

## Column names and casing

Table metadata stores names in the configured casing: on a `casing: 'camel'`
table, `table.primaryKey`, `table.columns` and the keys of a row are
camelCase. PostgREST only knows the database names. Every name that goes into
a query (an order term, a filter, a select list, an `on_conflict` target)
passes through `builder.column(table, name)` first, as `withTieBreaker` and the
default order in `src/core/repository.ts` do. A raw `table.primaryKey` in an
`OrderTerm` sends `order=customerId.asc`, which PostgREST rejects.

The tests that catch this need a camel table whose primary key is not `id`
(`customer_tags` in the fixtures); a table keyed on `id` hides the bug because
the name is the same in both casings.

## Per-request work

`connect()` and the repositories run on every request. Work that depends only
on the schema or the plugin list (column maps, default orders, plugin hook
arrays) is computed once per table and cached in a `WeakMap` keyed on the
table or the plugin list, not rebuilt inside a method.

## Plugin order and hook copies

`guards()` must see the query as the caller wrote it, so it declares
`enforce: 'first'` and `orderPlugins` runs it before every `pre` plugin; a new
`pre` plugin that rewrites queries never needs to know about it. Mutation hooks and `mutation`
listeners get a copy of the returned rows (`cloneRows` in
`src/core/repository.ts`), which keeps invariant 5 without trusting each
hook. Copy plain objects and arrays only: Temporal values are immutable and
`structuredClone` drops their prototype.

## Cross-tenant contexts

A request context is data that adapters, jobs and callers build, so a plain
key such as `{ allTenants: true }` in it could come from a payload or claims.
Skipping the tenant scope for a whole connection goes through
`allTenantsContext(context)` in `src/core/plugin.ts`, which sets a module
symbol that JSON can't produce and `$with` copies. `tenant()` and tenant
buckets check it with `spansAllTenants`; per-call opt-outs stay
`{ allTenants: true }` in the call options.

## Block extension points

Every block uses the same four extension points, so a new block adds entries
instead of a new mechanism:

- **Events.** Add the type to `BlockEventMap` (`src/core/block-events.ts`) and
  call `emitBlockEvent` after the work succeeds or is refused. The data never
  holds secrets (invitation tokens, webhook secrets), and handlers only
  observe.
- **Policies.** A decision the app can make is a `Policy` run through
  `decide()` (`src/core/policy.ts`), which fails closed. Never call the
  callback directly; a throw must deny, not escape.
- **SQL hooks.** List the hook in the module's `names.hooks` and render it
  with `ctx.hook(name, args)`; `ctx.emit(...)` writes the outbox event and
  renders nothing without the outbox.
- **Swappable parts.** An interface the app can replace carries
  `apiVersion: 1`, a conformance kit in `src/testing/kits`, an
  entry in `tests/core/extensibility.test-d.ts` and a row on the interfaces
  page.

## Considered and rejected

Earlier audits raised these and the code settled them. Don't reopen one
without new evidence.

- **`actingAs` mints `service_role` sessions.** By design: it trusts its
  caller like `admin()`, and the docs say to call it only after the
  signature check and the lookup (`guides/without-a-session.mdx`).
- **The auth memo grows without bound.** `secretIds` holds 64 entries with
  eviction, and `clearVerifiedTokens()` clears the URL, JWKS, secret and
  HS256 caches (`src/auth/resolve.ts`).
- **No statement timeout on the direct path.** `createPostgres` takes a
  per-role or single `statementTimeout` and `idleInTransactionTimeout`, and
  `SessionOptions.statementTimeout` overrides it per call.
- **`begin()` leaks a transaction when `set_config` fails.** The catch rolls
  back and the `finally` releases the client (`src/postgres/pool.ts`).
- **`https_proxy` in the webhook safe-fetch is an SSRF vector.** Proxy
  variables are the standard convention.
- **Chunked writes coerce a null count to 0.** Only inserts are chunked, and
  every insert plan returns a number.
- **The sessions, mfa, grants, actor and rls-guard modules are untested.**
  `sql-modules.integration.test.ts` covers them; only `realtime-tables` has
  no behavioural test.
- **`tracedFetch` is missing from `otel`, or `checkReceipts` keeps stale
  push tokens.** Both are wrong: `tracedFetch` is public and tested, and
  `checkReceipts` prunes.
- **29 `raise exception` sites stay inline.** `raise` can't reproduce them
  byte for byte (multi-line `using`, no errcode, computed hints); its doc
  comment in `src/sql/shared.ts` names the shapes. The inline grants in
  `rate-limit.ts`, `grants.ts`, `permissions.ts`, `workflow-sdk.ts`,
  `webhooks-out-sql.ts` and `audit-api.ts` differ from `revokeTable` the
  same way.
- **`functionRoute` takes the name, and `basePath` prefixes it.** The name
  is the deployed function's directory, which the handler doesn't know. A
  per-route `basePath` opt-out waits for an app that needs it.
- **`tablesOf` and two sequential loops could be faster.** `tablesOf` is
  cached, and running the loops in parallel changes which error is
  reported first.
