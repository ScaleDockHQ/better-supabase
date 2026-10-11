---
"better-supabase": patch
---

`suspendAccount` with `suspended: true` bans the user and keeps their sessions, so Auth answers refresh and `GET /auth/v1/user` with `user_banned`, `sessionStatus` returns `"banned"` and `bs.proxy({ endedSession })` redirects with `reason=account_banned`. Deleting the sessions made Auth answer `session_not_found`, so a suspended user read as `"ended"`. The `sessions` SQL module's `session_active()` already refuses a banned user's tokens. `suspended: false` now ends the sessions kept during the ban before it lifts it, so a reinstated user signs in again, and `ended` is `0` on a suspension. Pass `endSessions: true` to delete the sessions on suspension too, for apps without the `sessions` module. Doctor's BS106 description and the docs now say that `fromPolicies` makes only tables with RLS on service-only.
