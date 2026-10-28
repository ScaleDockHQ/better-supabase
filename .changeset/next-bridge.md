---
"better-supabase": minor
---

`toNextRoute(entries, handler)` and `toNextAction(entries, action)` from `better-supabase/next` run `@supabase/middleware` entries (`withRequiredClaims`, `withSupabaseClient`, `withCors`) around a Next.js route handler or Server Action. A route handler returns a `Response` or a value and gets the route `params`. An action reads the request from `headers()`, writes the entries' cookies through `cookies().set`, and throws `NextActionRejected` when an entry answers first.
