---
"better-supabase": minor
---

A support session lookup now serves the lookups that follow it for one second, for the same admin and token, so a render that builds many contexts loads the session once instead of once per context. A stop, revoke or removed permission applies at once on the instance that ran it and within one second on every other instance. Concurrent lookups of the target's claims share one call, and a failed load is never reused. Each lookup that reaches the store counts as a `support_sessions` call in the request's database stats.

`supportSessions({ unavailable: 'throw' })` makes `support.resolve` and `support.current` throw `SupportUnavailableError` when the session or the target's claims can't be loaded, so an app can fail closed instead of running the request as the admin. The default, `'admin'`, keeps answering `undefined`.
