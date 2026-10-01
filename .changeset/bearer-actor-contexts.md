---
"better-supabase": minor
---

Name the OAuth client or agent behind a bearer token. A user session now carries `actor` and `delegation`, read from `client_id`, `scope` and the RFC 8693 `act` chain the way PermDock's `actorOf` and `delegationOf` read them. A malformed `act` chain resolves to `{ kind: 'invalid', reason: 'actor' }` and a 401, so `InvalidReason` gains `'actor'`: an exhaustive `switch` over it needs the new case. The `scopes` guard option on `next.route`, `next.action` and the edge, Hono and oRPC adapters answers 403 with an RFC 6750 `insufficient_scope` challenge when a delegated token lacks a scope; the user's own token is not limited. `forbidden` errors and Problem Details carry the needed `scopes`. `better-supabase/server` now exports `toSession`, `AuthSession`, `ActClaim`, `SessionActor` and `SessionDelegation`. A new monorepo guide shows one runtime package that owns `defineSupabase`, with domain packages typed from its `db`.
