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

Frameworks the adapters type structurally (React Router, SvelteKit, Nuxt,
h3, Express, Fastify, Koa, Astro) stay out of this change. Each needs a
conformance test against the real framework before it gets a range;
declaring one without that would break strict installs on majors that work.

## Alternatives considered

Keeping them as devDependencies only gives apps no signal at all. Making
them regular dependencies installs every SDK in every app and breaks
invariant 1. Wide `*` ranges satisfy package managers but say nothing, which
is the problem this fixes.

## Consequences

A new major of an integration needs the peer range, the catalog pin and the
structural type updated together, and the conformance test proves it. Apps
on a major outside the range see a warning even if the part we call still
works; they can allow it with `peerDependencyRules.allowedVersions`. Revisit
the framework list once each framework has a conformance test.
