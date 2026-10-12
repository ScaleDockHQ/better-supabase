---
"better-supabase": minor
---

Support sessions that pass their expiry are now ended and recorded. The `support-sessions` SQL module adds `expire_support_sessions()`, for the service role only, which ends every running session past `expires_at` through `end_support_session(id, 'expired')` (so each gets its `support.ended` audit entry) and returns them. `bs.support.expire()` runs it through the store's new optional `expire()` (the SQL store calls it over `postgres.admin`) and emits `support.ended` with `endedBy: "expired"` for each session, and `bs.support.expireRoute({ secret })` serves it to a cron caller. A store without `expire()` fails with `SUPPORT_EXPIRE_UNSUPPORTED`, and `testSupportSessionStore` checks that `expire()` leaves running sessions alone.
