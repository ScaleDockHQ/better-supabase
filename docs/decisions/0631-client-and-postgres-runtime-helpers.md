# 0631: Add useOptimisticAction, onEnded, onRejoin, sharedPostgres, a verified ssl option and member reads

- Status: accepted
- Date: 2026-11-10

## Context

The second audit listed small runtime items that CentraKit builds by hand: an optimistic action
hook, a reaction to an ended session, a refetch after a realtime reconnect, one Postgres pool per
process, verified TLS in `/postgres`, and render reads that don't depend on every column of an
owned table (ADR 0591).

## Decision

- `useOptimisticAction(action, { state, update })` in `better-supabase/react` is `useAction` over
  React's `useOptimistic`. It returns `optimistic` and `confirmed` next to the `useAction` handle.
- `useSessionWatch({ onEnded })` replaces the reload for an ended session, a ban or a sign-out. A
  claims change still refreshes the router.
- `useBroadcast` and the other bindings take `onRejoin` and `rejoinOnLoad`. `startBroadcast` calls
  `onRejoin` when a channel joins again after a drop, and on the first join with `rejoinOnLoad`.
- `createPostgres({ ssl })` takes `true` (verified), `false`, or `{ ca, rejectUnauthorized }`.
  `sharedPostgres(options)` keeps one pool per process and connection string on `globalThis`.
- The module read tracker records `array.includes(string)` as one `member` read, so a render that
  asks whether a table has a column depends on that answer and not on every column.
- `maskSql` keeps its last 24 results per mode.

## Measured

`upgrade` on the CentraKit fixture, owned-column case: 32 modules rendered before, 30 after.
Cold `upgrade` 1.18 s before and 1.10 to 1.16 s after, inside run-to-run noise, so the `maskSql`
memo is not a gain worth claiming. The remaining 30 renders read the arrays by other means
(`new Set(layout.ownColumns[table])` in app-tables and view-columns), which this does not change.

## Not done

A result mapper that changes the data type, tenant from the URL, cache tags for RPC payload reads,
the bulk-actions and board lane controllers, the context factory, the route kits, the API key on
`ctx.auth`, `observedFetch` and batch block reads touch `src/next` and `src/server`, where the
server workstream is changing the definition and the proxy. They stay open.

## Consequences

`useOptimisticAction` needs React 19. `sharedPostgres` ignores later options for a known string.
