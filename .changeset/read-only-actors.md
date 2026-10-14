---
"better-supabase": minor
---

A read-only support or impersonation session can no longer write. Every security definer function granted to `authenticated` or `anon` that writes checks `better_supabase.actor_may_write()`, or `authorization.functions.actorMayWrite` when a provider sets it. The same check is added to generated write policies. Writes that succeeded during those sessions in 0.8.0 now fail with `ACTOR_READ_ONLY` (`42501`). `read_only: false`, an agent actor and a signed-in user without `act` still write. Reads are unchanged. `start_support_session`, `end_support_session` and `expire_support_sessions` stay callable so the session can be left.
