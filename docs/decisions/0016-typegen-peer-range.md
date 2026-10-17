# 0016: Declare postgrest-typegen as a peer range

- Status: accepted
- Date: 2026-10-11

## Context

Invariant 11 pinned `@supabase/postgrest-typegen` to one exact version in
both catalogs, so the published `peerDependencies` named `0.4.0` and nothing
else. An app with `strictPeerDependencies` that installed 0.4.1, for example
because another tool needed it, failed to install better-supabase, even when
it never ran `gen`. The other peers declare ranges; this was the only exact
peer.

## Decision

The peers catalog in `pnpm-workspace.yaml` declares `>=0.4.0 <0.5`. The
default catalog and `TYPEGEN_VERSION` (`src/cli/introspect/typegen-version.ts`)
stay exact, so the repo builds, tests and runs the parity test against one
release. At runtime `gen` reads the installed release (`typegenVersion()` in
`src/cli/introspect/typegen.ts`) and prints a notice when it differs from
`TYPEGEN_VERSION`. Doctor reports any installed peer outside its range as
BS601, and `getting-started/peers.mdx` lists every peer, its range and the
subpaths that need it; `tests/peers-page.test.ts` keeps the page in line with
the catalog.

## Alternatives considered

- **Keep the exact pin.** It guarantees byte-identical output but breaks
  installs for apps that pin a neighbouring release for other reasons.
- **Drop the floor and accept any 0.x.** postgrest-typegen is alpha, and a
  minor release can change the generator API the CLI calls.
- **Move typegen into a separate CLI package.** ADR 0007 put the CLI in the
  library to keep one install; a package split for one peer reverses that.

## Consequences

Apps on another 0.4 patch install cleanly and get a notice when their
`database.types.ts` may differ from `supabase gen types`. Bumping
`TYPEGEN_VERSION` still needs the parity test, the copy's type test and a
changeset; a new minor also widens the peer range. Revisit when
postgrest-typegen reaches 1.0 and follows semver for its generator output.

## Addendum: 0.6.0

The pin moved to 0.6.0 and the range to `>=0.6.0 <0.7`. The floor moved
with it instead of widening, because 0.6 changes the generated types (view
column nullability) and adds `rpcFunctions`, which older releases don't
write. `rpcFunctions` is derived from `functions`, so the CLI drops it
wherever it reorders, renumbers or filters functions, and the generator
resolves it again. Supabase CLI 2.121 writes `ComputedFields`, so the parity
test only normalizes the `__InternalSupabase` key that `--local` omits.
