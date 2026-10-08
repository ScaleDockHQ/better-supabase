---
"better-supabase": minor
---

`endSessions(sql, userId)` and `suspendAccount(admin, sql, userId, { suspended })` from `better-supabase/server`, also as `server.endSessions(userId)` and `server.suspendAccount(userId, { suspended })`. `endSessions` deletes the user's `auth.sessions` rows and refresh tokens. `suspendAccount` bans the user in Auth and ends every session in one call, and when resuming it ends any sessions left from before the ban, then lifts it, so lifting a ban no longer revives refresh tokens issued before it. Both need the server's `postgres`, and `createNext` also drops the user's cached sessions.
