---
"better-supabase": minor
---

The definition from `createSupabase()` no longer carries the code that turns it into a `db`. `definition.connect()` and `registerTable()` call a connection runtime that the client, the servers, the adapters and `better-supabase/testing` install when you import them, so a `next/proxy` consumer drops from 47.7 KB to 26.9 KB gzip (library code only). `createProxy()` no longer bundles the PostgREST executor, the query builder or the repositories.

Code that imports only `better-supabase` and calls `definition.connect()` now throws a `TypeError` until it imports a client or server entry. In a script or test, import `createClient`, `createServer` or a testing helper first.

`ProxyOptions.after` also receives the request as its third argument, so a proxy built with `createProxy()` no longer closes over the incoming request:

| Old                             | New                                      |
| ------------------------------- | ---------------------------------------- |
| `after: (response, auth) => {}` | `after: (response, auth, request) => {}` |

The first two arguments are unchanged, so existing `after` functions keep working.
