# 0036: Declare every SDK integration as an optional peer

- Status: accepted
- Date: 2026-10-17

## Context

better-supabase integrates with SDKs it never imports at the top of a runtime
entry: it declares the slice it calls as a structural type (ADR 0009) or loads
the package on first use (invariant 12). Until now some of them were peers
and some were only devDependencies. `@openfeature/server-sdk`,
`@supabase-labs/middleware-openfeature`, `@vercel/connect`,
`@ai-sdk/anthropic` and `@powersync/common` were devDependencies, so the
package said nothing about which majors it supports. When one of them shipped
a breaking major, an app upgraded without a warning and found out at runtime.
The Flags SDK adapter (ADR 0035) adds `flags` to that list.

## Decision

Every SDK an entry types structurally or loads lazily is an optional peer:
pinned exactly in the default catalog for the tests, with a range in the
`peers` catalog that covers the majors the conformance tests run against,
and `optional: true` in `peerDependenciesMeta`. The library still imports
none of them, so invariant 1 holds: an app that never uses the subpath never
installs the peer, and an app that does gets a peer warning (or, with
`strictPeerDependencies`, an install error) when its version leaves the
range.

`tests/optional-peers.test.ts` lists these integrations and fails
when one stops being an optional peer and a devDependency.
`tests/optional-peers.test-d.ts`, `openfeature.test.ts` and the
Flags SDK type test check each structural type against the peer's real types
at the pinned version, so a Renovate bump that breaks a contract fails CI
before the range is widened. `getting-started/peers.mdx` lists every peer.

The frameworks the adapters type structurally follow the same rule: React
Router, SvelteKit, H3, Nuxt, Astro, SolidStart, TanStack Start, Elysia,
Express, Fastify and Koa. `tests/frameworks.test-d.ts` hands each adapter's
output to the framework's real API at the current major. A range that still
covers the previous major (SvelteKit 2, H3 1, Nuxt 3, React Router 7) is
checked in the `tests/types/frameworks-previous` workspace, because
SvelteKit declares its types as an ambient module and two majors can't share
one TypeScript program. Majors no conformance test runs against (Astro 6,
SolidStart 1) are outside the ranges.

The first run of these tests found drift the structural types had hidden.
SvelteKit 3 moved `Handle` to `@sveltejs/kit/hooks`, and our `handle`
didn't accept SvelteKit's `resolve`. TanStack Start's `next()` may return
without a promise. Nitro 3 (H3 2, SolidStart 2) puts the Cloudflare bindings
on `event.req.runtime.cloudflare.env`, so the H3 2 and SolidStart adapters
read no env there. Astro allows any string as `quality`.

## Alternatives considered

Keeping them as devDependencies only gives apps no signal at all. Making
them regular dependencies installs every SDK in every app and breaks
invariant 1. Wide `*` ranges satisfy package managers but say nothing, which
is the problem this fixes.

## Consequences

A new major of an integration needs the peer range, the catalog pin and the
structural type updated together, and the conformance test proves it. Apps
on a major outside the range see a warning even if the part we call still
works; they can allow it with `peerDependencyRules.allowedVersions`. A new
framework major either joins the tested set (the previous one moves to
`tests/types/frameworks-previous`) or stays outside the range.
