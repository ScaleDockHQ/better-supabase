---
"better-supabase": minor
---

Names are now the same in every adapter. The definition from `defineSupabase` is `betterSupabase`, and every runtime instance an adapter creates is `bs`. They live in `lib/supabase/index.ts`, `lib/supabase/server.ts` (with `import "server-only"` in Next.js) and `lib/supabase/client.ts`, which is what `better-supabase init` now writes. The old names have no aliases; the compiler points out each one. [Naming](https://bettersupabase.com/docs/concepts/naming) lists the conventions.

| Before                                                                | After                                                                                         |
| --------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `createBrowser`, `BetterBrowser`, `BrowserOptions`, `BrowserAuth`     | `createClient`, `BetterClient`, `ClientOptions`, `ClientAuth`                                 |
| `<BetterSupabaseProvider browser={browser}>`, `BrowserLike`           | `<BetterSupabaseProvider client={bs}>`, `ClientLike`                                          |
| `client.sb` and the `sb` option of `testExecutor` and the test plugin | `betterSupabase`                                                                              |
| `next.server()`                                                       | `bs.context()` (pass a `Request` to read it instead of the incoming one)                      |
| `next.serverFor(session, { token })`                                  | `bs.contextForSession(session, { token })`                                                    |
| `BetterEnv` and `bs.handle()` (Hono)                                  | `HonoEnv` and `bs.handler()`                                                                  |
| `bs.toORPCError()`                                                    | `bs.toOrpcError()`                                                                            |
| `HandlerOptions` (Edge)                                               | `MiddlewareOptions`, shared by Hono, oRPC and Edge and exported from `better-supabase/server` |
| `handler` (MCP)                                                       | `endpoint`                                                                                    |
| `Queries`, `CreateQueriesOptions`, `queries.key`                      | `BetterQueries`, `QueriesOptions`, `queries.$key`                                             |
| `Postgres`                                                            | `BetterPostgres`                                                                              |
| `DefineSupabaseOptions`                                               | `SupabaseOptions`                                                                             |
| `repository.$table`                                                   | `repository.$tableName`                                                                       |

`createHono`, `createOrpc`, `createEdge` and `createMcp` now keep the claims and profile types from `.claims()` and `.userMetadata()`, so `c.var.auth`, `context.auth`, the edge handler's `auth` and MCP's `ctx.auth` are typed by your schema. `better-supabase/next` also exports the `LiveCountSeed` type that `bs.liveCount()` returns.
