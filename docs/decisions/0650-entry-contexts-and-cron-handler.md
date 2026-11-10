# 0650: Build contexts from one entry union and guard cron routes with cronHandler

- Status: accepted
- Date: 2026-11-10

## Context

A context comes from four methods of the server (`context`, `contextFromResolution`, `contextFor`
and, for the service role, `contextFor` with a secret caller), and each cron route in the blocks
(`cronRoute`) guards its own secret. An app's own scheduler route had to rebuild both. The
performance audit item `p5b-runtime` asked for one context factory and a cron route kit.

## Decision

- `entryContext(bsb, entry)` takes a `ContextEntry` (`request`, `resolution`, `auth`, `cron`) and
  calls the matching method. The switch is exhaustive and ends in a `never` check. `cron` runs as
  `{ kind: "secret", keyName }`, with `"cron"` as the default name.
- `cronHandler(bsb, { name, secret }, run)` reuses `core/cron-route.ts`, so it answers 405 and 401 the
  way the block routes do, and runs `run(ctx, request)` with the cron context.
- Both are plain functions that take the server, as the account helpers do (ADR 0604), so a route
  that doesn't use them doesn't bundle them.
- Not built: a public API route kit. `withBetterSupabase(bsb, { allow: ["apiKey"] })` already verifies
  the key and puts it on `ctx.auth`. Feeding `observedFetch` into `ctx.stats()`: `ctx.stats()` already
  records each Data API call through the executor, and the supabase-js clients share one `fetch`, so a
  per-context wrapper would count those calls twice. The process-level `observedFetch` stays the tool.

## Alternatives considered

- Methods on `BetterServer`: they grow the type of every server for apps that never use them.
- A `job` entry kind: `forContext` returns a `Db`, not a context, so it can't join the union.

## Consequences

Four exports of `better-supabase/server` (two functions, `CRON_KEY_NAME` and two types).
