# 0292: Give each first-party generator a subpath and declare its library as a peer

- Status: accepted; extends 0036
- Date: 2026-11-07

## Context

`zod()`, `valibot()`, `jsonSchema()`, `standardSchema()`, `factories()` and
`nuqs()` are exported from `better-supabase/config`, so a config that wants one
imports the whole config surface. The files two of them write import `zod` or
`valibot` at runtime, although neither library was a declared peer, so an app
found out about a wrong major when its own type check failed. `nuqs` was already
an optional peer with a tested range. Part 12 of the plan also describes a
`Generator` contract at `apiVersion: 2`, moved to a public kit, which is a larger
change.

## Decision

This change is the packaging step that needs no new contract:

- **Six subpaths**, one entry per generator, each re-exporting the generator
  and its option types from `src/generators/<name>/index.ts`:
  `better-supabase/generators/zod`, `/valibot`, `/json-schema`,
  `/standard-schema`, `/factories` and `/nuqs`. They are runtime entries, so they
  import no Node built-ins. They are listed in the exports map, `tsdown.config.ts`,
  the size baseline, the export snapshot (`api/exports.json`) and
  `tests/entries.test.ts`, and the validation page documents them.
- **`zod` (`>=4 <5`) and `valibot` (`>=1 <2`) are optional peers** with those
  tested ranges in the `peers` catalog and `tests/optional-peers.test.ts`, next to
  `nuqs`. The ranges follow what the generators write: `z.guid()`, `z.int()` and
  the `z.iso` formats need zod 4, and the pipe API needs valibot 1. `doctor` checks
  them like every optional peer.
- **`gen` prints a notice** when a configured generator's library is installed
  outside its range (`generatedLibraryNotices`). A library that isn't installed
  gets none.
- **`better-supabase/config` keeps exporting the generators** for now. The old
  path goes with the other removals in Part 9, together with a codemod that moves
  the imports.

## Not done

The `apiVersion: 2` contract (capabilities instead of `validators: true`,
structured-clone-safe input, worker-safe generators), the public kit
`better-supabase/generators` with `testGeneratorPlugin`, `defineFramework`
registrations, `tests/validation-plugins` and the boundary rule against
`generators/shared.ts`. Each needs the generator pipeline's stage split (Part 7)
first, and the pool.

## Alternatives considered

- **Separate packages** for each generator. One release train and one version
  keep the contract in step, as 0047 chose for the CLI contract.
- **Required peers.** An app that uses none of the generators would be told to
  install zod. Optional peers warn only the app that installed a library outside
  the range.

## Consequences

A config imports the generator it uses, and a wrong zod or valibot major shows up
in `gen` and `doctor` before the build. Each subpath adds its size to the
baseline (6.5 to 17.9 kB gzip), because the entries share no chunk with the
config entry. A later change that moves the helpers into a shared chunk lowers
them.
