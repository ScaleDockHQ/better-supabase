# 0635: Split the connection runtime from the definition

- Status: accepted
- Date: 2026-11-10

## Context

`createProxy()` reads only `definition.sessions`, but `core/define.ts` held the whole `BetterSupabase`
class, including `connect()` and the 700 lines behind it: the PostgREST executor (37 KB), the query
builder (26 KB plus 17 KB), the repositories, search, batching and RPC decoding. Every entry that
imported `createSupabase()` bundled them (ADR 0604 measured only 1.8 KB less from moving the account
helpers).

## Decision

`core/define.ts` keeps the data-only definition: schema, plugins, events, options, `claims`,
`userMetadata`, `mapError`, `buckets`, `blocks`, `use`, `defineRpc`, `on`, `cache`, `spec` and
`executorOptions`. `connect()` and `registerTable()` call a slot that `core/define-runtime.ts` fills.
The entries that build a `db` (the client binding, `createServer`, the upstream entries, the
transaction helper, the read-set probe, the PowerSync compiler and the testing helpers) call
`provideConnectionRuntime()` once at module level; the unit tests install it in a setup file.
`createProxy()` and the sessions runtime never import it.

The definition is not a separate data-only object with free functions (the plan's wording): the class
and its generics stay, so generated code and every adapter keep working unchanged. Only the code moved.

`ProxyOptions.after` takes the request as a third argument, which lets the example build its proxy
once with `createProxy()` instead of closing over the request.

## Measured

Library code only, min+gzip, supabase-js external (`tests/bundle/baseline-shipped.json`):

| Consumer                | Before | After  |
| ----------------------- | ------ | ------ |
| next proxy              | 47,740 | 26,872 |
| next + client           | 92,002 | 92,990 |
| hono                    | 70,533 | 71,443 |
| react + query           | 42,085 | 43,013 |
| saas client with blocks | 62,449 | 63,352 |

The proxy passes the 30 KB target. Consumers that connect pay about 1 KB for the second module. The
example app's proxy entry (`.next/server/middleware.js`, chunks it loads, example proxy on
`createProxy(app)` instead of the full server): 2,289,595 to 1,234,686 raw, 660,301 to 369,196 gzip,
520,937 to 297,459 brotli. It enters `tests/next-build/server-baseline.json` as `(proxy)`.

## Not done

`react + query` stays at 43 KB, not 30 KB. The browser client builds a `db`, so it needs the runtime;
reaching 30 KB means splitting the executor and the repositories by table use (ADR 0262 lazy tables),
which this change does not attempt. The next-build baselines for the other routes were not rerun:
`next build` fails on main at `/api/v1/openapi.json` and `/api/mcp` ("unknown table customers"),
before this change.
