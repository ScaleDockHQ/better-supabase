---
"better-supabase": minor
---

Adds `authErrorKind(error)` to `better-supabase/auth` (`retryable`, `session-missing`,
`invalid-credentials`, `rate-limited`, `banned` or `unknown`; it reads `code` and `status` first).
The block auth failures and `deleteAccount` use it, so a 429 is a `rate_limited` error. The
`SupportApi` methods accept a `SupportCaller`: an `AuthState`, or `{ token, claims }`. `bsb.action`
takes `guard(tenant, ctx)`, which runs after authentication and the permission check, and
`result(outcome)`, which maps the `ActionResult`.
