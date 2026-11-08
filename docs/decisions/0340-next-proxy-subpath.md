# 0340: Ship the proxy as its own subpath

- Status: accepted
- Date: 2026-11-07
- Amends: 0117, 0316

## Context

`proxy.ts` ran through `bsb.proxy()`, which lives in `createNext`. That module
imports the sign-in flows, record bindings, the collector and the resource
router, so an app's proxy bundle carried Server Component code.

## Decision

`better-supabase/next/proxy` (`src/next/proxy/index.ts`) exports `createProxy()`
and the proxy helpers. The handler moves to `proxy-handler.ts`, and the request
bookkeeping (collector, stats header, `after()` flush) to `proxy-runtime.ts`;
`createNext` calls both, so `bsb.proxy()` behaves as before. `createProxy` builds
its own `createServer` from the same options and imports nothing from
`create.ts`. It imports no Node built-in, so it is a runtime entry.

## Consequences

The `next proxy` entry in `tests/bundle/baseline-shipped.json` is smaller than
`next + client`. An app that uses both `createNext` and `createProxy` builds two
servers unless it passes `server`; the session memo and the JWKS fetch are shared
per process (ADR 0116), so the cost is one more object graph.
