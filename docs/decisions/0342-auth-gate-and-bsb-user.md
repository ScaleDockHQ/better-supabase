# 0342: Gate the app layout with AuthGate and bsb.user

- Status: accepted
- Date: 2026-11-07
- Amends: 0095, 0316

## Context

Client Components that need the user's id or email read a session through a
provider the layout builds by hand, and a layout that awaits the session blocks
the App Shell.

## Decision

`bsb.user()` returns a `GateUser` (`src/next/user.ts`) and applies the entry the
way `bsb.cached()` does, with `cacheLife({ stale: 300 })`. A library can't carry
a `"use cache"` directive (Next.js doesn't compile `node_modules` by default),
so the app wraps it in a `"use cache: private"` function and passes that to
`AuthGate` as `user`; this differs from the spec, where `AuthGate` calls
`bsb.user()` itself. `better-supabase/next/auth-gate` holds the Server Component;
its provider and `useUser()` sit in `next/auth-gate/user`, a `"use client"`
entry that tsdown keeps external, like `react/session`. Because `useUser()`
reads a resolved promise with `use()`, no client code imports the data layer.

## Consequences

The status code of a signed-out visitor is the proxy's; `AuthGate` takes an
optional `check` for a response status before the first `<Suspense>`, and a
request API there makes the layout dynamic. The user is never more than the four
fields; the token stays behind `bsb.cached()`.
