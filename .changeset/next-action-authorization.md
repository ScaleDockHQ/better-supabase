---
"better-supabase": minor
---

`bs.action()` and `bs.route()` take `requireTenant` and `authorize`. `requireTenant: true` refuses a caller without an active tenant (`forbidden`, `code: "NO_TENANT"`) and types `ctx.tenant` as a string. `authorize(session, input)` refuses with `forbidden` (`code: "NOT_AUTHORIZED"`) when it returns `false`. The context also carries `session`.

`bs.require(options)` is `bs.context()` for Server Components that only some callers may see: it takes `allow`, `aal`, `scopes`, `requireTenant` and `authorize`, and calls `unauthorized()`, `forbidden()` or `notFound()` for a refused caller.

`bs.cached({ tables, id })` tags a private cache entry by table (`bs:<table>@<tenant>` and `bs:<table>@*` under an active tenant), so the `updateTag` after a mutation drops it.

`useSessionChange(changed, router, { refreshToken: supabase })` refreshes the browser session before it re-renders, for changes only the next token carries, such as an organization switch.

`tenantOf(session)` from `better-supabase/next` and `better-supabase/react` reads the active tenant of an `AuthSession`.
