# 0450: Resolve auth once per scope, pipe nested verbs, and split the server entry

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
at once, and `AsyncResult.pipe` runs chained calls as one `AsyncResult`: `bind`
unwraps each step and stops the pipe at the first error. The tags block's
`create` verb uses it first.

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

## Alternatives considered

Keeping re-exports from `server` kept the bundle cost, which was the problem.
Making `pipe` a generator-based `do` notation needs a runtime helper in every
verb and reads worse than `await bind(...)`.

## Consequences

`tests/server` counts `resolveAuth` calls and asserts the new `from` and `pipe`
semantics. The `./server` size baseline drops and the three new entries have
their own. Imports of the moved names need a path change; the codemod is
follow-up work. Single-function block verbs, `ServerContext<App>`, `adapterBase`
and the per-instance generated modules stay with the rest of the server runtime
work and use ADRs 0451 to 0459.
