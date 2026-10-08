---
"better-supabase": patch
---

Fixes across the client, native and server adapters:

- `clearOnUserChange` resets rows fetched as anon while the session was still loading, and keeps them when the session resolves signed out.
- `bindClient` returns a `dispose()` that removes its auth listener, and `bindClient` and `createClient` take a `staleTime`.
- `createQueries` takes a `scope`, appended to every key, so two clients over the same schema keep separate caches.
- `useAction` returns a stable `run` and `reset`, and `useBroadcast` resubscribes when `self` changes.
- `liveQuery` rejoins a channel that errors or times out, with backoff up to 30 seconds, then refetches (`retry: false` turns it off).
- `secureStorage` passes `storeOptions` (keychain service, accessibility) to expo-secure-store, and keys that map to the same safe name no longer collide.
- `bs.middleware()` in Expo takes `publicPaths` and never redirects the sign-in route to itself.
- The PowerSync executor decodes integers beyond the safe range as strings, checks the abort signal before it runs a query, and `sqliteTables` honors `tableName`.
- Storage drops cached signed URLs when an object is written, moved or removed, settles an aborted upload with an error, and `sweep` streams the listing and removes orphans after the walk.
- `bs.resources()` on the edge serves `PUT`, `PATCH` and `POST` requests that carry a body, and the CORS wrapper passes the host env through.
- `toH3` keeps the status and headers a handler set on `event.res`, and reads the env from `event.context.cloudflare.env`. `toReactRouter`, `toTanStackStart` and `toExpo` take an `env` option, and `toElysia().wrap()` and `toOrpc()` take the host env as their second argument.
- `bs.action()` with a per-input `tenant` no longer resolves `NextOptions.tenant` first, and `bs.route()` takes `refresh` for routes outside the proxy's matcher.
- The MCP server rebuilds cached visible tool lists after `mcp.tool()` registers a tool.
