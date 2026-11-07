---
"better-supabase": minor
---

`better-supabase/next/auth-gate` exports `AuthGate`, a Server Component for the app layout that renders a `<Suspense>` around one `bsb.user()` promise, and `useUser()` for Client Components. `bsb.user()` returns `{ id, email, name, organizationId }` or `null`, never the token or the session, and sets `cacheLife({ stale: 300 })` like `bsb.cached()`. `AuthGate` takes the loader as `user`, redirects or refuses a signed-out visitor, and keys the subtree on the user id.
