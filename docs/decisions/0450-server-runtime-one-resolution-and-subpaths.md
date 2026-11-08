# 0450: Resolve auth once per scope and split the server entry

- Status: accepted
- Date: 2026-11-08
- Amends: 0008, 0234

## Context

The server runtime paid for work that nothing used. `createNext` ran a token
snapshot pass and then a full resolution for each read of `context()`, and
derived `claims()` through a third pass. `AsyncResult.from` waited one
microtask before it started, and block verbs that nest `andThen` built one
promise chain per step. `better-supabase/server` exported 84 names, so every
route that imports `createServer` loaded account, support and CSV helpers.

## Decision

`createNext` resolves a request once per read of `context()` or `claims()`,
and derives the claims from that resolution. `AsyncResult.from` starts its run
at once. A pipe helper for nested block verbs is deferred: the first version
grew the example app's client routes past the never-grow baseline.

`better-supabase/server` loses the account and support helpers
(`deleteAccount`, `endSessions`, `suspendAccount`, `lastSignIns`,
`supportSessions`, `supportStorage`, `sessionStatusRoute`) to
`better-supabase/server/accounts`, the CSV helpers to `better-supabase/server/csv`
and the rate-limit header helpers to `better-supabase/server/rate-limit`. The
old names have no alias.

The block builder checks port uniqueness and resolves every consumed port to
its provider once per block set (`wiringOf` in `blocks/create-blocks.ts`) and
keeps the result, so each later builder reads it. Plugin `afterMutation` events
copy the returned rows on the first read of `rows`, as the `mutation` event
already did.

`server.context()` skips the entry fold when `tenant` and `support` are unset:
it resolves, then builds the context. The fold stays for composite servers.

## Alternatives considered

Keeping re-exports from `server` kept the bundle cost, which was the problem.

## Consequences

`tests/server` counts `resolveAuth` calls and asserts the new `from` semantics. The `./server` size baseline drops and the three new entries have
their own. Imports of the moved names need a path change; the codemod is
follow-up work. Single-function block verbs, `ServerContext<App>`, `adapterBase`
and the per-instance generated modules stay with the rest of the server runtime
work and use ADRs 0451 to 0459.
