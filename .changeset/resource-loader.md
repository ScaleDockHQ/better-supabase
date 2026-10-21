---
"better-supabase": minor
---

A `permission` on an action, route, loader or oRPC middleware can now be checked against the row it acts on. Pass `resource: (input, ctx) => AuthorizationResource` next to `permission`: it runs after the session and `requireTenant` checks, gets the validated input and the request's context (`db`, `session`, `tenant`), and its return value replaces the default `{ type: "action" }` or `{ type: "route" }` resource. A loader that throws refuses the caller: a `DbException` keeps its error (such as `not_found`), and any other throw refuses with `forbidden` and `code: "RESOURCE_UNAVAILABLE"`. Every adapter supports it, and `bs.middleware()` in `better-supabase/orpc` now passes the procedure's input to the checks. The loader's context type is exported as `ResourceLoaderContext`.
