# 1221: Keep reads across requests in a shared tier filled under RLS

- Status: accepted
- Date: 2026-11-23

## Context

`bsb.cached` and `bsb.remote` keep a read for one render or one Next.js cache
entry. A read that outlives a request and a deploy (a dashboard count, a
settings page) had nowhere to live, so apps reached for a service-role client
and a hand-rolled cache, which skips RLS. The Postgres cache handler sent two
PostgREST requests per hit and could drop a tag expiry when two writes marked
the same tag. Twenty concurrent misses on two instances ran twenty fills. A
fill through a session handle was missing from the request stats, the first
request of a process paid for the JWKS, PostgREST and pool connections, and an
authorizer could not tell whether RLS would check a write again.

Two constraints hold for everything below: no service-role read for tenant
data, so RLS stays the authority, and a shared entry is filled through the
caller's own client. `@vercel/functions` stays an optional peer typed
structurally, and runtime entries stay free of Node built-ins (invariants 1
and 6).

## Decision

`bsb.kept(fn, options)` keeps a read in a `KeptStore` across requests and
deploys. The function runs as the caller under RLS, and the key carries the
user, the tenant and the authorization version. A write to one of `tables`
expires its tags in the kept store as well as in the Next.js cache. Three
stores ship: `memoryKeptStore()`, `vercelRuntimeCacheAdapter(getCache)` and
`postgresKeptStore()`. An entry over 2 MB, 128 tags or 256 bytes per tag is
not stored and is reported to `kept.onSkip`.

`share: "tenant"` lets callers who hold the same grant in a tenant read one
entry. The authorization provider declares which tables it shares in its new
`tables` field, and the `shareKey` hook names the grant. The first caller fills
the entry through its own client; inside that fill any other table, function
call or raw client answers `SHARE_REFUSED` and nothing is stored. Doctor BS428
and `expectTenantShare` guard the declaration.

`postgresCacheSql()` adds `bsb_cache_get` (one call per read) and
`bsb_cache_mark_tags` (`greatest()` per tag, so concurrent expiries never drop
one), a pool transport and `delete(key)`. A missing entry is filled once: one
fill per process, and a `bsb_cache_leases` row across processes, which the
Runtime Cache adapter imitates with a best-effort lock entry. The request
stats count session-handle fills, tag calls and one record per kept or remote
entry. `warm()` loads the JWKS and opens the PostgREST, pool and flags
connections from `register()`. The authorizer context gains `enforcement:
"rls" | "definer"`, unset meaning `definer`.

`scripts/probe-vercel-tags.ts` and the example's `api/probe/vercel-tags`
route answer whether `updateTag` already expires Runtime Cache entries on
Vercel. Until a maintainer runs it with `BSB_TAG_PROBE_SECRET`, writes expire
both, in batches of 16 tags per call.

## Alternatives considered

- A service-role fill shared by everyone in a tenant: the fastest option, and
  the one apps were already building, but it moves the access decision from
  RLS into the cache key. Rejected by the constraint above.
- One entry per user only: safe, but a tenant of 200 users fills the same
  dashboard 200 times. `share: "tenant"` keeps that as the default and the
  fallback.
- Advisory locks for the cross-instance lease: they bind the lease to one
  connection, which a PostgREST or pooled transport does not keep. A lease row
  with an expiry works through every transport.
- Leaving the Vercel expiry to `updateTag`: unproven until the probe runs, and
  a stale entry is worse than a few more tag calls.

## Consequences

Reads that outlive a request run as the caller and stay correct when a policy
changes, because the authorization version is part of the key. Measured on the
local stack, a Postgres cache hit is one call (p50 1.4 to 1.7 ms through
PostgREST, 0.2 ms through a pool), and 20 concurrent misses on two processes
run one fill instead of 20. Apps that used the Postgres handler must run
`postgresCacheSql()` again in a migration; until then the store falls back to
the two-request path and reports it once.

The Runtime Cache lease is best effort, so two Vercel instances can still fill
at once. A wrong `tables` declaration cannot leak rows the filling caller may
not read, but it can show one caller's rows to another holder of the same
grant; the doctor rule and `expectTenantShare` are the guards. If the probe
shows `updateTag` already expires Runtime Cache entries, drop the second expiry.
