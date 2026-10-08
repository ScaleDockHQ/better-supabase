---
"better-supabase": minor
---

`bs.routes` in `better-supabase/edge` types `ctx.params` from each route key (`"GET /customers/:id"` gives `{ id: string }`, a trailing `/*` adds `"*"`), and `RouteParams<Key>` is exported. The edge, Hono, oRPC and MCP examples use `bs.routes`, `bs.require` and `bs.authed` with roles, and `requiredRoles` with `hasRole`.
