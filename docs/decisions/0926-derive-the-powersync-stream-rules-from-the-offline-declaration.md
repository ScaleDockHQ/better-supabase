# 0926: Derive the PowerSync stream rules from the offline declaration

- Status: accepted
- Date: 2026-11-14

## Context

ADR 0920 declared `offline: true` on the eight blocks `powersync streams` supports, but the rules that pick each device's rows (whose rows, which extra conditions, which tables keep system rows) stayed in `src/cli/powersync/streams.ts` (EX-1318).

## Decision

`EntitySurface.offline` accepts `true` or an `EntityOffline` object (additive, `apiVersion` stays 1):

- `scope` is `user`, `self`, `tenant` or `readers`: the user's rows, the user's own row, the rows of the user's organizations, or the rows of the organizations where the user's roles hold the block's `read`.
- `where` lists `column = value` and `column is null` conditions, each optionally skipped on a table without the column.
- `systemRows` names a table suffix whose tenant-less rows sync next to the tenant's.

Each manifest declares its rules on its entity. `powersync streams` reads the same table from `src/cli/powersync/offline-rules.ts` with `offlineOf`, and `tests/blocks/entity-surface.test.ts` fails when a manifest and the table differ; the manifests can't import the table, because every block entry would then carry it (the bundle baseline grew by about a kilobyte). The care tables (observations, medications, activities), the teams and the profiles take their filters from the declaration. The progress note conditions of the activities block moved from the generator to the manifest.

## Alternatives considered

Generating every stream from the scope alone needs the joins the declaration cannot state, so the notification events and preferences, the membership role sets and organizations, and the attachment subject and reader rules stay in the generator.

## Consequences

A block author changes a stream's rows in the manifest, and the generated YAML is unchanged for the eight blocks. The joined streams remain hand-written; the audit row names them as the deferred part.
