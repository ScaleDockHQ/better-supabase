# 0522: Cap the Supabase JWKS cache at 600 seconds and expose purgeKeys

- Status: accepted
- Date: 2026-11-08
- Amends: 0116

## Context

ADR 0116 shares one JWKS fetch per process, cached for 300 seconds with a
30 second cooldown on a refetch for an unknown `kid`. Two gaps remained: an app
could set `cacheSeconds` to any value for a Supabase project, which keeps a
revoked signing key verifying for that long, and nothing let an app forget a
key set after it revoked a key.

## Decision

- `core/jwks-cache.ts` caps the cache of a Supabase Auth key set (a URL ending
  in `/auth/v1/.well-known/jwks.json`) at `SUPABASE_JWKS_MAX_CACHE_SECONDS`
  (600). The default stays 300, and other issuers keep their own value.
- `purgeJwks(url?)` forgets one key set, or all of them. `purgeKeys(url?)` in
  `better-supabase/server` is the public form: with a URL it purges that set,
  without one it also clears the imported HS256 secrets.
- The review confirmed what 0116 already does: an unknown `kid` refetches once
  per cooldown, concurrent callers share one fetch, and a failed fetch keeps
  the keys already known. Tests in `tests/core/jwks-cache.test.ts` now pin each.

## Alternatives considered

- Lowering the default to 60 seconds. Rejected: the unknown-`kid` refetch
  already handles rotation, and a shorter default adds fetches on every cold
  instance.
- Purging on every verification failure. Rejected: a stream of forged tokens
  would defeat the cooldown.

## Consequences

An app that set `cacheSeconds` above 600 for a Supabase project now refetches
every 600 seconds. Nothing else changes for existing apps. `upgrade` rewrites no
module, and no data migration is needed.
