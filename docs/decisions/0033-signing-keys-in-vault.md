# 0033: Keep signing keys in Vault and sign in TypeScript

- Status: accepted
- Date: 2026-10-16

## Context

Shared-signal streams, Ed25519 webhooks (Standard Webhooks `v1a`) and
app-issued JWTs need an asymmetric key per owner, a JWK Set that receivers
fetch, and rotation that never strands a token that is still valid.
Postgres has no Ed25519 or ECDSA signing in `pgcrypto`, and runtime entries
import no Node built-ins (invariant 6).

## Decision

The `signing-keys` SQL module stores the private JWK as a Vault secret
(`bs:signing:<kid>`) and the public JWK, owner, state and `publish_until`
in `signing_keys`. Every function is security definer and service-role
only. An after-delete trigger deletes the Vault secret. Keys are created,
imported and used with WebCrypto in `src/core/jws.ts`, so the private key
leaves the database only for the service role, and only when a signer loads it
(cached for `cacheSeconds`). The `kid` is the RFC 7638 thumbprint.
`signJwt` notes each `exp`, rounded up to the hour, so a retired key stays in
the JWKS until its last token expires plus `jwksGrace`.

The webhooks block takes a structural `RawSigner`, not the signing-keys
client, so the two blocks don't import each other.

## Alternatives considered

- Sign inside Postgres with `pgsodium`: it is deprecated on Supabase, and
  its key handling differs per project.
- Store private keys in a table column, encrypted with an app key: that is a
  second secret to rotate, and Vault already does this on every project.
- Keep keys in a cloud KMS: that is a provider dependency in the core.
  `WebhookSigner` and `RawSigner` still let an app plug one in.

## Consequences

Any service that holds the service role can read a private key, which is
already true of webhook secrets. A KMS-backed signer is a `RawSigner`
implementation away. Revisit when Supabase Vault offers sign-only keys.
