---
"better-supabase": minor
---

`better-supabase/hono` adds `bs.app()`, a `Hono` app typed with the adapter's `Env` and with `bs.onError` installed, and the type-only `bs.Env` for apps that build their own. After `@supabase/server`'s `withSupabase`, `bs.middleware()` reuses its verification of the bearer token when the stored claims are that token's payload, then runs its own claims, `act` and `userMetadata` checks.

`clearOnUserChange(queryClient, auth)` in `better-supabase/query` removes the `["bs"]` queries when the signed-in user changes, for apps without React; `BetterSupabaseProvider` uses it.

A bucket with `tenant` now checks paths on the client too: `upload`, `download`, signing, `remove`, `reserve` and `list` refuse a path in another tenant's segment, or any path when the connection has no tenant, with a `forbidden` error before calling Storage. Pass `{ context }` or `{ tenant }` to `connect()`, or `{ allTenants: true }` for cross-tenant admin work; `deleteAccount` does the latter. `client.path(target)` returns the checked path.

Jobs record the enqueuing request's actor and tenant: `enqueue(queue, payload, { context })` and `schedule(..., { context })` store them next to the payload, and the handler gets them as `job.context`, ready for `db.$with(job.context)`. A job without a tenant gets the `tenant()` plugin's `onMissing` unless the worker runs with `allTenants: true`.

`actor()` fills an `impersonatedBy` column (generated from `impersonated_by`, the column the SQL kit's `track_actor` stamps) from the impersonating admin, and clears it on writes without one.

Event sink sends are tracked on `betterSupabase.events` (`pending`, `settled()`). Next.js routes and actions hand them to `after()`, and edge handlers to `waitUntil`: the Workers `ctx`, or `createEdge(..., { waitUntil })` on Supabase.

The PermDock guide has oRPC and Hono recipes that refuse a procedure or route without a permission.
