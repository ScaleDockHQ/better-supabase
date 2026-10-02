---
"better-supabase": minor
---

`checkSession(sql, auth)` from `better-supabase/auth` and `better-supabase/server` confirms that a user token's session still exists in `auth.sessions`, and returns an `unauthorized` error with code `SESSION_REVOKED` when the user signed out or the session was ended. Call it before actions you can't undo, such as deleting the account. Nothing calls it by default, so other requests still verify tokens without a round trip.
