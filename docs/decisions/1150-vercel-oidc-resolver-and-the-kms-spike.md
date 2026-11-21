# 1150: Verify Vercel OIDC tokens as an AuthResolver and leave the KMS exchange out

- Status: accepted
- Date: 2026-11-21

## Context

The plan asked for a Vercel OIDC resolver that signs a Supabase JWT with
Vercel KMS, so a Vercel Function can call Supabase as a caller. A spike checked
the pieces. Vercel signs its OIDC tokens (RS256) with keys at
`https://oidc.vercel.com/.well-known/jwks`, with the claims `project_id`,
`environment`, `owner_id` and `sub`. Supabase third-party auth needs an OIDC
issuer with discovery and asymmetric keys with a `kid`, and it takes up to 30
minutes to pick up key changes. Nothing confirms that Vercel KMS signs
arbitrary payloads under a key Supabase can discover, so a token Supabase
accepts could not be produced.

## Decision

`vercelOidcResolver` in `better-supabase/vercel-passport` is an `AuthResolver`:
it verifies the token against Vercel's JWKS (the shared key cache) and returns
an `apiKey` caller built by the app's `map`. It gives Supabase no token and
adds no Vercel dependency. The Passport cookie (`_vercel_passport`, chunked,
checksummed) is read behind `headers: "cookie"` or `"all"`. The KMS exchange is
not built. Revisit it when Vercel documents signing for a third-party issuer.

## Alternatives considered

- Sign a Supabase JWT with a KMS key: rejected, the signing API and the issuer
  discovery Supabase needs are not documented.
- Read the cookie by default: rejected, a browser sends it on its own, so it is
  opt-in.

## Consequences

A Vercel project can call an API that runs better-supabase and be mapped to a
tenant and scopes. Row Level Security does not see the caller as a Supabase
user.
