# 1030: A lazy connection for support sessions

- Status: accepted
- Date: 2026-11-15

## Context

`sqlSupportStore` takes its `admin` and `asUser` connections synchronously, and
`createPostgres` lives in `better-supabase/postgres`, which imports `pg`. An app
that builds the store in a module every server route imports puts `pg` in all
of those bundles, although only the support routes ever query. The example's
Next.js server baselines stayed at the measured values for that reason (lane
O3, EX-1318 note).

## Decision

`lazyPostgres(load)` from `better-supabase/server` returns the two connections
`sqlSupportStore` needs and calls `load` on the first query. It keeps the
loaded connection, and a failed load is not kept, so the next query tries
again. It imports nothing from `pg`. The caller owns the dynamic import.

`supportSessions` does not change: its `store` stays synchronous, because it
reads `store.claims`, `store.request` and `store.expire` to decide what the
store supports, and a promise of a store could not answer that.

## Alternatives considered

- Make `supportSessions({ store })` accept a promise or a loader: the optional
  store methods decide behavior (`policy.approval`), so the server would have
  to load the store before it knows what the store can do.
- Move `pg` behind a lazy import inside `createPostgres`: the pool is created
  eagerly and used by the repositories, which want it loaded.

## Consequences

The example loads `pg` on the first support query and its shared server bundles
no longer carry it. The lazy helper adds a few lines to `better-supabase/server`.
