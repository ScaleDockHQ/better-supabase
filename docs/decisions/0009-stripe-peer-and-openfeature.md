# 0009: Load Stripe lazily as an optional peer and type OpenFeature structurally

- Status: accepted
- Date: 2026-10-06

## Context

The billing and usage blocks create Checkout and portal sessions, update
subscription quantities and send meter events, so they talk to Stripe. The
flags block serves flags to OpenFeature clients and to `withOpenFeature` from
`@supabase-labs/middleware-openfeature`. Invariant 1 keeps the core free of
runtime dependencies beyond `@standard-schema/spec` and the Supabase
packages, and invariant 6 keeps runtime entries on WinterTC APIs.

## Decision

`stripe` is an optional peer, pinned exactly in the default catalog with a
range in the `peers` catalog. `src/blocks/stripe.ts` declares the slice of
the SDK the blocks call as `StripeClient` and loads the package through a
variable specifier the first time a block needs it, with Stripe's fetch HTTP
client. An app that already has a client passes it as `stripe`; a missing
install throws a message that names both ways. This is the lazy load listed
in invariant 12.

The flags block never imports OpenFeature. `createFlagClient` returns the four
`get*Details` methods that `@supabase-labs/middleware-openfeature`'s
`FlagClient` and the OpenFeature server `Client` share, and
`createFlagsProvider` returns an object shaped like an OpenFeature `Provider`.
`@openfeature/server-sdk` and `@supabase-labs/middleware-openfeature` are
devDependencies for the conformance and composition tests only.

## Alternatives considered

Calling the Stripe REST API with `fetch` would avoid the peer but repeat the
SDK's form encoding, retries, idempotency headers and webhook signature
check. Requiring the app to always pass a client works, and stays supported,
but makes the common case longer. Importing `@openfeature/core` for its types
would add a runtime package for types the blocks can declare in a few lines.

## Consequences

Apps without billing never install Stripe, and bundles that pass their own
client don't contain a second copy. A Stripe major that changes one of the
methods in `StripeClient` needs the peer range and the interface updated
together. Revisit if OpenFeature publishes a types-only package the blocks
could depend on instead.
