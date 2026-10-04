---
"better-supabase": patch
---

Breaking (types): `SessionActor` is a union on `kind`: `oauth-client` (with `chain`), `support` (with `sessionId`, `readOnly` and `reason`) and `impersonation` (with `reason`), and `Impersonator` gains `kind`. An exhaustive `switch` on `session.actor.kind` needs the two new cases.

Support sessions and impersonated sessions mark their `act` claim: `supportClaims` writes `act.kind: "support"` and `actingAs` writes `act.kind: "impersonation"`. `actorOf` reads them as their own actor kinds instead of OAuth clients, `session.impersonator` follows `actorOf`, so an OAuth client or agent chain is no longer shown as an impersonator, and `session.delegation` and the `scopes` guard apply to `oauth-client` actors only. An `act` with another `kind`, or a support level without `session_id`, makes the session invalid (`reason: 'actor'`). A support token minted by 0.5.0 (`session_id` without `kind`) still counts as a support session until 0.6. `supabaseClaimFixtures` from `better-supabase/testing` holds a support session (writable and read-only), an impersonated session, an OAuth client and an agent chain, each valid against PermDock's `supabase-claims-v1.json`.
