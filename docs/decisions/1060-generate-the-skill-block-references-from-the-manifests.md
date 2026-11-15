# 1060: Generate the skill block references from the manifests (lane Y5)

- Status: accepted
- Date: 2026-11-15

## Context

The consumer skill `better-supabase` had seven hand-written references and none
per block family, so an agent learned a block's entities, events and ports from
the docs only (EX-1350). `blocks-and-presets.md` also listed presets by hand,
and the glossary words lived only in `api/naming.json`. A hand-written list of
blocks drifts with every release. `ui-recipes.md` already shows the fix: it is
generated and `recipes:check` fails when it is stale.

## Decision

`scripts/build-skill-references.ts` writes one `catalog-<category>.md` per
category of `BLOCK_CATALOG` under the skill's `references`, from the block
catalog and the preset manifests: client export and subpath, requires, works
with, composed blocks, entities, tables, permission keys, events, ports,
actions, env keys and providers. It also writes `catalog-index.md`, with the category, preset and
glossary tables, from `BLOCK_CATALOG.presets` and `api/naming.json`;
`blocks-and-presets.md` links to it.

`pnpm skill-references` writes the files. `pnpm skill-references:check` is a
task of `pnpm verify` and of `verify.yml`, and fails on a stale file or a
`catalog-*.md` file no category writes. The skill reads the catalog the
package ships, so the references match the version the app installs.

The other references (adapters, frontend, troubleshooting, native auth) teach
tasks and stay hand-written. A hand-written reference does not list blocks,
entities or events; it links to a generated one.

## Alternatives considered

- Reading `BLOCK_CATALOG` at run time only. An agent that cannot run code or
  has no installed package gets nothing; a file is also cheaper to load.
- One file with every block. It is about 2,700 lines, which is too large to
  load for one question.
- Method signatures in the references. They come from the TypeScript types, not
  the manifests, and the docs pages already carry them.

## Consequences

An agent finds a block's entities, permission keys and events in one small
file. The tarball grows by about 2,700 lines of Markdown. A manifest change
needs `pnpm skill-references` in the same commit, like `pnpm catalog`.
