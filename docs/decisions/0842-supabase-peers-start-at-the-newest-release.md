# 0842: Start the Supabase peers at the newest release

- Status: accepted
- Date: 2026-11-13
- Amends: 0016

## Context

The Supabase peers had floors from earlier releases and, for the 0.x
packages, an upper bound at the next minor release. An app that installed a
newer `@supabase/postgrest-typegen` or `@supabase/mcp-server-supabase` failed
strict peer checks, although the CLI only loads typegen and the MCP server
runs as its own process. The repo also ran CLI 2.x notes and a legacy-engine
CI job that CLI 3.1.0 made redundant.

## Decision

Every Supabase peer starts at its newest release that is older than
`minimumReleaseAge`: supabase-js, auth-js and realtime-js `^2.119.0`,
`@supabase/server` `^1.9.2`, `@supabase/config` `^1.6.1`,
`@supabase/postgrest-typegen` `>=0.8.1` and `@supabase/mcp-server-supabase`
`>=0.16.1`. The last two have no upper bound. The default catalog keeps exact
pins, and `TYPEGEN_VERSION` is 0.8.1, so `gen` still prints a notice for any
other typegen release (ADR 0016, invariant 11).

`supabase` stays at 3.1.0, the only stable 3.1.x release. On 3.1.0 the stack
engine's Realtime allows private channel joins and typegen agrees with the
CLI on view column nullability, so the CI `realtime` job on the legacy engine,
the `stackEngine` test gates and the view normalization in the parity test
are removed. The expired `minimumReleaseAgeExclude` entries are removed.

## Alternatives considered

- Keep the upper bounds on the 0.x packages. Each new typegen or MCP server
  release would then break strict installs until better-supabase shipped a new
  range, and the notice in `gen` already warns about a different typegen.
- Move `@supabase/mcp-server-supabase` to 0.17.0. It was published inside the
  release-age window, so it waits for the next bump (invariant 14).

## Consequences

Apps on older Supabase releases have to upgrade before they take this
release. A typegen release that changes `GeneratorMetadata` fails the copy's
type test (`tests/config/generator-metadata.test-d.ts`), which is the signal to
move `TYPEGEN_VERSION`.
