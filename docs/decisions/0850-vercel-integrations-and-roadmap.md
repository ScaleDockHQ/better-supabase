# 0850: Integrate Vercel's SDKs through structural adapters and versioned ports

- Status: accepted
- Date: 2026-11-13

## Context

Apps on Vercel asked for BotID and Firewall on the auth routes, Passport
identities, project domains for the domains block, Functions helpers, KMS for
signing keys and Blob for files. Invariant 1 allows no runtime dependency
beyond the Supabase packages, ADR 0010 keeps blocks SDK-neutral, and
invariant 10 versions every interface an app or library implements. ADR 0033
rejected a cloud KMS because it put a provider dependency in the core, and
ADR 0633 bounds how long a stale JWKS may be served.

## Decision

Every SDK is an optional peer, typed structurally and passed in by the app; no
module imports it, so no entry loads one lazily either.

- `better-supabase/vercel-security`: `botIdGuard({ checkBotId })` and
  `firewallRateLimit({ checkRateLimit, id })` guard the sign-up, OTP and
  magic-link routes, answering with Problem Details: a 403 (`BOT_DETECTED`,
  `FIREWALL_BLOCKED`) or a 429 with `Retry-After`. A failed BotID check
  refuses by default and a failed or unknown Firewall rule lets the request
  through by default; both follow `onError`. `combineGuards` and `withGuards`
  compose them.
- `better-supabase/vercel-passport`: `verifyPassport(request, options)`
  verifies the Passport token with the library's own JWS code and the shared
  JWKS cache, so it needs no SDK at runtime, and calls an app-supplied
  `resolveUser({ iss, sub, claims })`. The library stores no mapping.
- `DomainProvider` (`apiVersion: 1`: `add`, `verify`, `remove`, `status`) in
  `better-supabase/blocks/domains`, with `vercelDomainProvider(sdk, {
  projectId, teamId })` over the project domain methods of `@vercel/sdk`.
  `createDomainsAdmin({ provider })` calls the provider's `verify` only after
  the TXT check passes, and gains `add`, `remove` and `status`.
- `@vercel/functions`: an `attachDatabasePool` option on `createPostgres` (a
  Node entry), and a `JwksStore` that `sharedJwks` reads before a fetch and
  writes after one, with `vercelRuntimeCache(getCache)`. A stored key set
  keeps the time of its original fetch, so ADR 0633's bound holds across
  instances; a purge ignores older stored copies, and a failing or slow store
  falls back to the fetch.
- `KeyProvider` (`apiVersion: 1`: `sign`, `signJwt`, optional `noteExp`) in
  `better-supabase/blocks/signing-keys`. `vaultKeyProvider` is the default
  and is ADR 0033 unchanged; `vercelKmsKeyProvider(kms, { issuer })` signs in
  Vercel KMS, so the private key never reaches the app. This answers ADR
  0033's objection: the KMS is a port the app plugs in, not a core dependency.
- `FileStore` (`apiVersion: 1`: `put`, `get`, `delete`, `signedUrl`, plus the
  optional `head` and `signedUploadUrl`) in `better-supabase/storage`, used by
  the attachments and drive blocks through `files`. `supabaseFileStore` is the
  default and `vercelBlobStore(blob)` the alternative. Postgres still decides
  who may upload: the blocks reserve the path through the SQL module, and
  `confirm_attachment(id, object)` (attachments module version 10) accepts the
  object's size and type from the service role only, checked against the
  bucket's limits, for a file Storage doesn't hold.
- The UI recipe pages link each recipe's registry items to v0's open endpoint.
  The markup stays out of the registry (ADR 0031), so a recipe without glue
  items has no link.
- Each port has a conformance kit in `better-supabase/testing`
  (`testDomainProvider`, `testKeyProvider`, `testFileStore`), and the blocks'
  lint rule refuses imports of `@vercel/sdk`, `@vercel/kms` and `@vercel/blob`.

## Alternatives considered

- Import the SDKs lazily: the adapters call a handful of functions, and a
  structural type keeps the bundle and the peer matrix smaller. The peer type
  checks in `optional-peers.test-d.ts` catch a drifting SDK.
- Wrap `@vercel/passport`'s `verifyIdentity`: it reads `process.env` and
  Vercel's request context, which a runtime entry can't assume, and it keeps
  its own JWKS cache outside ADR 0633's bound.
- Keep `confirm_attachment` unchanged and let the app mark external uploads:
  that moves the upload rule out of Postgres. Trusting a size the browser sends
  was rejected for the same reason.
- Put the Vercel adapters in their own subpaths: the blocks already accept
  structural ports (`vercelQueueProvider`), and a separate entry per provider
  would split each block's docs.

## Consequences

Apps install only the SDKs they use, and every port can take another
platform's implementation without a release. The attachments module change
needs `better-supabase upgrade` and a migration. Passport and KMS key set URLs
are Vercel's to change; Passport's issuer and JWKS URL are exported constants
an app can override with `jwks`.

The Next.js example's sign-up form runs BotID through a Server Action. It
starts BotID in the form, not in `instrumentation-client.ts`, so only the
sign-up route loads the script: its first load goes from 672639 to 678685
bytes raw (216596 to 218698 gzip). The customers detail route grows from
1495594 to 1498995 bytes raw (422004 to 423124 brotli, as CI measured it)
with the attachments client's `FileStore`. The next-build server baseline,
which also carries the queue scheduler change (ADR 0849), is raised to the sizes measured on this branch for 280 of 353
routes (median 12.2 KB raw, 4.2 KB gzip; `/api/queues/block-ticks` grows
most, 37.0 KB raw). It gains `/api/auth/callback`, `/api/jobs/drain` and
`/api/queues/schedules`, and no route is lowered.

## Roadmap kept out of this PR

- Remaining checks: that `gatewayOptions` sets AI Gateway's `gateway.user` and
  tags from the request context; `@chat-adapter/state-pg` compared with our
  Chat SDK state; Streamdown as a UI recipe only; Agent Skills.
- Frameworks: a Nitro 3 and h3 v2 adapter in the community tier, with Nuxt
  following when it moves to Nitro 3; the SvelteKit and TanStack Start example
  apps. FastAPI is not planned.
- A queue-backed provider for eve's dynamic schedules. eve 0.83.3 ships
  `defineDynamicSchedules` in `eve/experimental/schedules`, but its
  `ScheduleProvider` contract gives a provider `target.deliver` only during a
  management call, and eve fires timed occurrences only through its own
  Vercel Queues consumer route. A provider over the queue block's
  `ScheduleProvider` could store, list and invoke schedules but not fire them
  on time, so it waits for eve 1.0 (held back by the trust policy until about
  2026-11-30) or a public delivery entry point.
- No integration surface, not planned: Vercel Drop, Vercel Agent, the Vercel
  Plugin, Bot Management rulesets and Global Config.
