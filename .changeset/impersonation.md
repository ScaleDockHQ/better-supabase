---
'better-supabase': minor
---

Audited impersonation: `server.actingAs(userId, claims, { actor, reason })` adds an RFC 8693 `act` claim, the `audit` SQL kit module records `impersonated_by` and `impersonation_reason`, and `track_actor(table, impersonated_by => 'column')` stamps the admin on each write. `session.impersonator`, `context.actor.impersonator` and `impersonatorOf(claims)` expose it for banners and plugins. Works over `better-supabase/postgres` only.
