---
"better-supabase": minor
---

`actorOf(claims)` and `delegationOf(claims)` are exported from `better-supabase/server`, with the `ActorOutcome` type, so another library can read an `act` and `scope` claim the way `toSession` does without building an `AuthState`.
