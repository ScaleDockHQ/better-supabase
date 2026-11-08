# 0331: Move the generators out of better-supabase/config

- Status: accepted; completes the Part 9 step of 0292
- Date: 2026-11-07

## Context

ADR 0292 gave each first-party generator a subpath and kept the old export in
`better-supabase/config` until Part 9 removed it. A config that imported `zod()`
from `better-supabase/config` pulled every generator into the config entry, and
Part 9 allows no alias.

## Decision

`better-supabase/config` stops exporting `zod`, `valibot`, `jsonSchema`,
`toJsonSchema`, `standardSchema`, `factories`, `nuqs` and their option types.
Apps import them from `better-supabase/generators/<name>`. The `generators`
codemod (`better-supabase codemod generators`) rewrites the imports, grouping
names by generator and keeping type imports and aliases, and lists every line of
a generator that still uses the `apiVersion: 1` shape of ADR 0330. The CLI imports
the generators from `src/generators` directly.

## Alternatives considered

- **Keep a re-export.** Part 9 forbids aliases, and the config entry would keep
  the size the subpaths were added to remove.
- **Fold the rewrite into a release-wide codemod.** The release codemod of Part 9
  does not exist yet; a named codemod runs today and the release one can call it.

## Consequences

The `./config` entry drops the generators' size in the baseline, and each
generator's cost lands only on the config that imports it. An app that still
imports from `better-supabase/config` fails its type check on the missing
export, and the changeset names the codemod.
