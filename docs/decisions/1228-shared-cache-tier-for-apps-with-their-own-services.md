# 1228: Close the shared cache tier's gaps for apps that build their own services

- Status: accepted
- Date: 2026-11-24

## Context

ADR 1221 shipped the shared cache tier in 0.85: `bsb.kept()`, `share: "tenant"`
through a guarded reader, the kept stores and the fill lease. An app on 0.82
with Next.js Cache Components on Vercel, an external authorization provider
and its own services found eight gaps. A tenant fill refused every database
function, so a page that loads in one RPC was kept per user. Public data had
no shared form without the service role. Reads inside `"use cache: private"`
had no test that they count. `./next` grew to 256.8 KB gzip. A service that
builds its `db` over its own Postgres pool bypassed the table guard. The
Runtime Cache lease could be taken twice, because the store is eventually
consistent. There was no probe for the kept store on Vercel and no single
guide from 0.82. The architecture invariants hold throughout: no service-role
read for tenant data, RLS decides every row, `@vercel/functions` stays a
structurally typed optional peer and runtime entries import no Node built-in.

## Decision

A provider may list `sharedFunctions`, each with the tables it reads and the
permissions those reads check. `kept()` and `remote()` accept them through
`functions`, and `$rpc` inside a shared fill calls only those. A function
share is sound only when the function returns the same rows for every holder
of the grant, so doctor BS430 requires `security invoker`, `language sql`, not
`volatile`, and a body that reads only the declared tables. The fill still
runs through the caller's client, so RLS checks every row.

`share: "public"` fills through the anon context of `bsb.public()` and keys
the entry on no user or tenant. Doctor BS645 reports a public entry on a
table that `anon` can't select, because that entry would cache an empty or
failed read for everyone.

`shareGuard(ctx, db)` in `better-supabase/server` applies the shared reader's
table guard to a `db` the app builds itself, and refuses a `db` that doesn't
run as the caller: another user, the service role or no session.
`inTenantFill` in `better-supabase/testing` runs a service the way a tenant
fill does, and the CentraKit fixture tests a customer service under the guard.

`postgresKeptLease()` in `better-supabase/cache-postgres` returns only the
lease of `postgresKeptStore()`, and `vercelRuntimeCacheAdapter` takes it as
its `lease` option. On the benchmark with writes that reach other instances
25 ms later, four instances fill four times with the Runtime Cache lock and
once with the Postgres lease (p50 103.0 ms against 82.8 ms).

`src/next/record.ts` loads the record block clients from `record-blocks.ts` on
the first record call. A fresh process evaluates `./next` in 93.1 ms instead
of 104.5 ms and loads 224.2 KB gzip instead of 256.8 KB. The import is listed
in `.agents/rules/lazy-imports.mdc` and retries after a failed load.

The probe route and `scripts/probe-vercel-tags.ts` time the kept store's
write, cross-instance read, deployment version, latency and a burst of tag
expiries. `--local` runs on `memoryKeptStore()`. The Vercel numbers wait for a
maintainer run on a preview deployment.

### Permission filters inside a shared function

Added after 0.85, when CentraKit's payload functions all failed BS430 because
each narrowed its rows with a provider helper that reads the caller. A
provider may list such helpers in `permissionFilters`, each with the position
of its permission key argument. BS430 admits a call to one when the key is a
string literal that the function's `permissions` lists, and refuses a key
built at run time.

The argument that this is sound: a shared entry is keyed on the tenant and
the share key, and the share key names the caller's grants for the entry's
`permissions` in that tenant. Two callers with the same key therefore hold the
same grants for every listed permission. A listed helper's result depends only
on the caller's grants for its key in the current tenant, so it returns the
same ids to both callers, and the function, whose other inputs are its
arguments and tables shared per tenant, returns the same rows. A literal key
is what makes the share key cover the call; a computed key could name a
permission the share key leaves out. The helper's own body is the provider's
promise, not doctor's: a helper that reads a user id, a row-level grant or the
clock breaks the argument, so the field's documentation says so and a
provider lists only helpers it can vouch for. RLS checks every row the fill
reads as the caller who fills the entry; it does not check the other callers
the entry serves, so a wrong declaration leaks rows between them, as any wrong
`sharedFunctions` entry does.

BS430 also reports every reason a function fails instead of the first, matches
tables and functions as `schema.name` through the function's `search_path`,
and admits a `better_supabase` helper that passes the same check on its own,
so the pure library helpers (`permission_matches`, `round_half_even` and 46
more) need no listing. `config functions --shareable <glob>` runs the check on
functions before they are listed. For it and for the recursive check,
introspection now reads the bodies of every `language sql`, security invoker,
non-volatile function in the read schemas when the config has a provider:
the root stack's snapshot grows from 38.71 MB to 39.12 MB, and the read takes
the same time (443 ms against 416 ms).

## Alternatives considered

- **A tenant function plus a per-user read.** Keep only the table reads shared
  and run every RPC per user. It is always sound, but a page that loads in one
  RPC then gains nothing, and the declaration plus BS430 makes the sound case
  checkable.
- **Public data through the service role.** Rejected by the invariants: the
  service role bypasses RLS, and an `anon` read keeps the policies in charge.
- **Wrap the app's pool in better-supabase.** It would take over a connection
  the app owns. `shareGuard` checks the `db` it is given instead.
- **A stronger Runtime Cache lock.** The Runtime Cache has no compare-and-set,
  so a lock entry there can't be exclusive. Postgres has one row per key.
- **Lazy-load more of `./next`.** `supportStorage`, the sessions and sign-in
  run at create time or synchronously, so loading them late saves nothing.

## Consequences

An app can share page RPCs, public lists and its own services without the
service role. A function share is only as safe as its declaration, which BS430
checks at doctor time and not at request time. The Postgres lease adds one
round trip to each miss and needs `postgresCacheSql()` for the leases table.
The first record call of a process pays for the import. We revisit the lease
when the Runtime Cache offers an atomic write, and the probe numbers when a
maintainer runs them on Vercel.
