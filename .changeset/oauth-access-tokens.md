---
"better-supabase": minor
---

`accessTokenResolver({ jwks, issuer, audience })` from `better-supabase/server` verifies RFC 9068 access tokens that another authorization server issued, next to `apiKeyResolver`. A verified token resolves to a user with `source: "oauth"`, and its `sub`, `client_id` and `scope` reach `ctx.sql` and `forContext` as claims, so the request runs as the user under row level security and a `scope` limits it like any OAuth client. The resolver fails closed on a wrong issuer or audience, an expired token, a missing required claim, a `service_role` role or a sender-constrained token, and can check a revocation list keyed by `jti` and grant. JWS verification also accepts RS256 and PS256 keys.

The new `oauth-server` block (`better-supabase/blocks/oauth-server`) stores what an authorization server needs: an RFC 7591 client registry with hashed secrets and registration tokens, authorization codes bound to an S256 PKCE challenge, RFC 8628 device codes, grants per user and client, and the revocation list. A replayed authorization code revokes its grant. The block issues no tokens; sign them with `createSigningKeys`. Install it with `better-supabase add oauth-server`. The pins are `SPEC_PINS.rfc9068`, `rfc7591`, `rfc7636`, `rfc8628` and `rfc9700`.
