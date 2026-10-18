---
"better-supabase": patch
---

`toSession` refuses an invalid `act` claim on a hand-built `AuthState` the same way `resolveAuth` does: the session is `{ kind: "invalid", reason: "actor" }` with code `ACTOR_INVALID`, never the user without an actor. Before, a malformed agent level (a `session_id`, an empty tool name, `tools` that is not a list) read as the plain user there. The `ACTOR_INVALID` message now names `agent` among the accepted kinds.
