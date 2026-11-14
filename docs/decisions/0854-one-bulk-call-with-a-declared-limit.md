# 0854: One bulk call with a declared limit

- Status: accepted
- Date: 2026-11-14

## Context

EX-1209 found three shapes for bulk work: an array overload (`tasks.remove`),
the `bulk-actions` block and per-block `*Many` calls. Each returned its own
result and none declared how many ids it takes, so a caller could not write
one bulk bar for every list.

## Decision

`src/core/bulk.ts` defines the one shape: `bulk(ids, action, options)` returns
`{ succeeded: string[], failed: { id, error }[] }` where `error` is a plain
`DbError`. The ids are made distinct, a list over the limit fails with the hint
`BULK_TOO_MANY` before anything runs, and one failing id never stops the others.
The limit is 500 unless the entity declares `bulk: { limit, actions }` in its
manifest `entities` entry. The `bulk-actions` block gets `bulk(ids, action,
{ organizationId, subjectType })` over its `bulk_apply` function, so a row that
the database refuses lands in `failed` with its hint. `run`, `start` and `apply`
stay for callers that need the per-row `results` or a background run.

## Alternatives considered

- Keep the array overloads and add a wrapper: three shapes would stay.
- Throw on the first failure: a bulk bar needs to show which rows failed.
- Raise the limit per call: a limit is a property of the entity, so the manifest
  declares it.

## Consequences

A list page writes one bulk bar against one result. Blocks migrate their
`*Many` methods to `bulk` in the category lanes; this change adds the contract
and the `bulk-actions` implementation and removes nothing, so it is not
breaking.
