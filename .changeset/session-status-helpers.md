---
"better-supabase": minor
---

`sessionStatus(request | accessToken, { url, publishableKey })` and `clearSessionCookies(request, response, { url })` from `better-supabase/ssr` and `better-supabase/server` run the ended-session check of `bs.proxy({ endedSession })` in any proxy or middleware. `sessionStatus` reads the bearer token or the session cookie, asks Auth (`GET /auth/v1/user`) and returns `"ended"` on a 401 or 403, `"active"` on a 2xx and `"unknown"` without a token, for an expired token, on network failures, timeouts and other statuses, so an Auth outage keeps the session. `clearSessionCookies` expires every chunk of the session cookie on the response and adds the no-store headers.
