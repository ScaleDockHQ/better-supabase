---
"better-supabase": minor
---

The browser client's `db` is smaller: `createClient` from `better-supabase/client` no longer carries `$many`, `$search`, `$stats`, `$decode` or `$decodeReadSet`, so `react` plus `query` ships 35.4 KB gzip instead of 43.1 KB. `client.db` is typed as `CoreDb`, so a call to a removed method fails at type-check time. The server, every adapter, `createNativeClient` and `better-supabase/testing` install the full `db` and are unchanged.

A filter tree (`FilterQuery`) passed to `where` needs `enableFilterTrees()` from `better-supabase/list` in a bundle that builds no server. The server installs it.

`gen` writes the composed block reads (`reads` and their argument and result types) to `blocks.reads.ts`, which imports no block, and `blocks.generated.ts` re-exports it. Define read sets over the app without blocks and import `reads` from `blocks.reads.ts`, so a route that runs a read set bundles only its own block set.

| Old                                                           | New                                                                      |
| ------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `client.db.$many(...)` in a `"use client"` file               | Move the read to a server function, or call `$run` once per spec         |
| `client.db.$search`, `$stats`, `$decode` in the browser       | Call them on the server's `db`                                           |
| `where: filterTree` in a bundle without a server              | Call `enableFilterTrees()` from `better-supabase/list` once              |
| `import { reads } from "./blocks.generated.ts"` in a read set | `import { reads } from "./blocks.reads.ts"` (the old import still works) |

`createNativeClient` is now its own function with the full `db` type. `provideConnectionRuntime` moved to `core/define-runtime-full`, and `provideLeanConnectionRuntime` is the browser's.
