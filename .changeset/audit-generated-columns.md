---
"better-supabase": patch
---

The audit docs show how an adopted log fills a column derived from the actor, such as `actor_is_platform_admin`, with a Postgres generated column over the mapped actor kind instead of a metadata key. An integration test confirms that `audit_event` fills it for service calls, support sessions and users.
