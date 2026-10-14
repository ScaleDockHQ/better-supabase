---
"better-supabase": minor
---

An RFC 8693 `act` level may be `{ kind: "agent", sub, tools }`. `agentClaims(claims, { agent, tools })` from `better-supabase/server` builds it on top of the user's claims, and agent runs carry it as `run.act`. An agent writes with the user's row level security unless its level sets `read_only: true`, and a `scope` on its token limits it like an OAuth client. The read-only check in every SQL module knows the new kind, so `sql sync` rewrites each installed module.

`inboxAdapter({ identities })` resolves each inbox contact before the handlers run and issues a run ticket for a contact linked to a signed-in user, which `ticketOf(message)` returns for `forContext({ ticket })`. `testAuthorizationHooks` also checks `automation.mayPublish` and that a support start cannot approve itself.
