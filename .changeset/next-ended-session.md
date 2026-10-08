---
"better-supabase": minor
---

`bs.proxy(request, { endedSession: { redirect, paths } })` signs out browsers whose auth session has ended. A token stays valid after its session is signed out elsewhere, revoked or deleted, so RLS that checks the session hides every row. With `endedSession`, document loads and the listed paths ask Auth (`GET /auth/v1/user`) whether the session still exists; on a 401 or 403 the proxy clears the session cookies and redirects to `redirect` with `?reason=session_ended`, or passes a signed-out caller to `protect` without `redirect`. Network and server errors keep the session. `shouldCheckSession(request, options)` tells which requests are checked, `server.resolve(request, { checkSession: true })` runs the same check, and the resolution's `sessionEnded` is `true` when it signed the caller out.
