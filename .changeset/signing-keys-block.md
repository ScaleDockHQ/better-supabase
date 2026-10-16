---
"better-supabase": minor
---

New `signing-keys` block (`better-supabase sql add signing-keys`, `better-supabase/blocks/signing-keys`): Ed25519 and ES256 keys per owner, with the private key in Supabase Vault and the public JWK in a service-only `signing_keys` table. `create` and `rotate` keep one active key per owner and retire the previous one. A retired key stays in `jwks(owner)` until the last `exp` that `signJwt` noted plus `jwksGrace` (`5 minutes`). `jwksResponse` serves the set as `application/jwk-set+json`, and `purge()` deletes keys no token can still need. `signer(owner)` signs raw bytes or compact JWTs in TypeScript with WebCrypto, and `verifyCompact` checks them against a JWK Set. Ed25519 keys sign as `EdDSA` by default, or as `Ed25519` (RFC 9864, pinned as `SPEC_PINS.rfc9864`).

Outgoing webhooks can sign with Ed25519 (Standard Webhooks `v1a`). `webhooks-out` 4 adds `signing` (`v1` or `v1a`), `format` and `credential_ref` columns to `webhook_endpoints`. A `v1a` endpoint is signed by the new `asymmetricSigner` option, which takes `standardWebhooksAsymmetric({ signer })`. It needs no secret and is dead-lettered when no signer is set. `verifyWebhook` accepts a `whpk_` public key, which `webhookPublicKey(jwk)` builds, in place of a `whsec_` secret.
