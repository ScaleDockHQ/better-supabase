---
"better-supabase": minor
---

The API keys block (`better-supabase/blocks/api-keys`) issues keys with a checksum, reports their state and authenticates REST routes.

- Keys end in a CRC-32 checksum, so `verify` and secret scanners reject a mistyped key without a lookup (`parseApiKey`).
- Keys report `state` (`active`, `grace`, `revoked`, `expired`) and `successorId` (`ApiKeyState`).
- `withApiKey({ keys })` is a pipeline entry that verifies the key and contributes `ctx.auth`, and `apiKeyClaims` and `apiKeyResolver` take a `claim` shape so the authorization provider reads the key's scopes.
- `options.scopes: "catalog"` limits scopes to the provider's permission keys, and the provider model refuses the `*` scope unless listed.
