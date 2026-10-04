---
"better-supabase": minor
---

Support mode: platform admins can view the app as a user. The new `support-sessions` SQL kit module records sessions in a table (or an adopted one), checks `is_platform('support.start')`, writes `support.started` and `support.ended` to the audit log and can call your access token hook for the target's claims. `createServer` takes `support: supportSessions({ store, authorize, claims, policy, cookie })`, which apps without support mode never bundle; while the `bs-support` cookie names a running session, contexts, sessions, actions and routes run as the target over Postgres, read-only by default, with an `act` claim that carries the session id. Next.js gets `bs.startSupport()`, `bs.stopSupport()` and `supportTag()`, React gets `useSupportSession()`, and `better-supabase/testing` gets `testSupportSessionStore`. The audit module records the session in a new `support_session_id` column; an adopted table maps `supportSession` to `null` when it has none.
