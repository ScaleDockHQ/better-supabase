# 0848: Start every peer range at the newest installable release

- Status: accepted
- Date: 2026-11-13
- Amends: 0036, 0094

## Context

The peer ranges in `catalogs.peers` started at the release that first had
the API an adapter calls, often several majors back, and the default catalog
pinned something newer. The conformance tests ran on the pin only, so the
floor of a range was a claim no test checked. Four frameworks kept their
previous major in range (SvelteKit 2, Nuxt 3, React Router 7, H3 1) and needed
a `tests/types/frameworks-previous` workspace, because SvelteKit declares its
types as an ambient module and two majors can't share one program.

## Decision

Every peer range starts at the newest release that passes the repo's
supply-chain policy (`minimumReleaseAge: 1440` and `trustPolicy:
no-downgrade`) when the range is set, and the default catalog pins that same
release, so the tests run on the floor. A range covers one major, or one
minor for a 0.x package; the ranges that already spanned 0.x minors (`eve`,
`@json-render/core`, `oxfmt`) keep their ceilings. The previous majors are
dropped: SvelteKit 2, Nuxt 3, React Router 7, NestJS 11, Stripe 17 to 22,
`expo-server` 55 to 57, undici 7, redis 5 and PowerSync 1.
`tests/types/frameworks-previous` and the `previous-majors` catalog are
gone.

Some ranges differ from that rule:

- `h3` stays `>=1.15.11 <3`. Nuxt 4.6.4 still runs on Nitro 2
  (`@nuxt/nitro-server` depends on `h3 ^1.15.11`), so `better-supabase/h3/v1`
  stays supported. `tests/frameworks.test-d.ts` checks it against H3 1.15.11
  through the `h3-v1` npm alias in the default catalog.
- `oxfmt` stays `>=0.66.0 <1`: `@supabase/postgrest-typegen` 0.8.1 declares
  `oxfmt` 0.66.0 as an exact optional peer.
- `@opentelemetry/api` starts at 1.9.1, not 1.10.0. `@supabase/lite` 0.11
  depends on `@sentry/node ^10.51.0`, and every Sentry 10 release pins
  `@opentelemetry/core` 2, which caps the API below 1.10.
- `trustPolicy` rejects every release of `@vercel/connect` after 2.5.0,
  `@vercel/functions` after 3.10.1 and `@vercel/oidc` after 4.0.1 until it is
  30 days old (`trustPolicyIgnoreAfter`): those packages published with
  provenance attestations before and without them since. So `@vercel/connect`
  starts at 2.5.0, `@vercel/functions` at 3.10.1 and `@vercel/kms` at 0.3.4
  (0.3.5 and later pin a rejected `@vercel/oidc`).
- The same rule holds back two upgrades. Workflow 5.5 depends on
  `@vercel/functions ^3.11.1`, so `workflow` stays on 5.4.0 and the Supabase
  World on the 5.1 world protocol. eve 0.84 and later peer on
  `@vercel/connect ^2.5.2`, and the 1.0 release candidates on `^2.7.0` (eve
  imports `connectTelegramCredentials`, which 2.5.0 doesn't export), so eve
  moves only to 0.83.3. Both move once the releases they need turn 30 days old:
  `@vercel/connect` 2.7.0 on 2026-11-30 and `@vercel/functions` 3.11.1 on
  2026-12-09.
- The Supabase peers keep the shape ADR 0842 gave them: `@supabase/config`
  `^1.6.1`, and `@supabase/postgrest-typegen` and
  `@supabase/mcp-server-supabase` as floors with no upper bound. The MCP
  server's 0.17.0 passes `minimumReleaseAge` on 2026-11-14, so its floor stays
  0.16.1 here.

`@ai-sdk/sandbox-vercel` 1.0.182 still depends on `@vercel/sandbox ^3.9.0`.
The library's own `@vercel/sandbox` moves to 4.0.0, and the adapter type check
in `optional-peers.test-d.ts` passes with the two copies side by side.

## Alternatives considered

- Keep the old floors. They promise compatibility with releases no test runs,
  and the previous-major workspace cost a separate install for four adapters.
- Add `minimumReleaseAgeExclude` or `trustPolicyExclude` entries for the
  Vercel releases. That bypasses the supply-chain policy (invariant 14) for
  packages whose provenance changed, which is exactly what the policy exists
  to catch.
- Allow eve 1.0 with a `peerDependencyRules` entry for `@vercel/connect`. eve
  imports an export that 2.5.0 lacks, so the allowance would hide a broken
  install.

## Consequences

Apps on an older release of a peer have to upgrade before they take 0.67;
`migration/0.66-to-0.67.mdx` lists each new floor. Every bump of a peer now
moves its floor too, so a range never claims a release the tests don't run.
The eve 1.0 and Workflow 5.5 upgrades wait for the dates above, and are a
plain catalog bump once they pass `trustPolicy`. Revisit the `h3` exception
when Nuxt moves to Nitro 3, and the `@opentelemetry/api` floor when
`@supabase/lite` moves off Sentry 10.
