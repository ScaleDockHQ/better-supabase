---
"better-supabase": minor
---

The signing-keys block signs through a versioned `KeyProvider` (`sign`, `signJwt`). `vaultKeyProvider` is the default and keeps today's behaviour, with the private keys in Supabase Vault. `createSigningKeys({ keys: vercelKmsKeyProvider(kms, { issuer }) })` signs in Vercel KMS instead, so the private key never reaches the app; `create`, `rotate`, `jwks` and the other key methods keep managing the Vault keys. `@vercel/kms` is an optional peer that you pass in, and `testKeyProvider` in `better-supabase/testing` checks your own provider.
