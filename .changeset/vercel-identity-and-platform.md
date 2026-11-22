---
"better-supabase": minor
---

Vercel integrations gain a Vercel OIDC `AuthResolver`, verdict handlers, deadline-aware Postgres statements, Blob options and framework guards. There are no breaking changes.

## Features

- `vercelOidcResolver` (`better-supabase/vercel-passport`) verifies a Vercel OIDC token and returns an `apiKey` caller from your `map`. `verifyPassport` can read the chunked `_vercel_passport` cookie with `headers: "cookie"` or `"all"`.
- `botIdGuard` and `firewallRateLimit` take `onVerdict`. `firewallRateLimiter` (`better-supabase/vercel-security`) is a `RateLimiter` backed by the Vercel Firewall.
- `createPostgres({ getDeadline, deadlineMargin })` cancels a statement that could not finish before the invocation ends.
- `vercelBlobStore` takes `ttlDays`, `cacheControlMaxAge`, `storeId` and `oidcToken`, and maps Blob's store, suspended and precondition errors to `DbError` codes.
- The Vercel domain provider reports `misconfigured` and the recommended `dns` records when the SDK has `domains.getDomainConfig`.
- `bsb.caller()` guards SvelteKit remote functions (pass `getRequestEvent` in `kit`). `bsb.guard()` is the guard for a TanStack Start function middleware.
