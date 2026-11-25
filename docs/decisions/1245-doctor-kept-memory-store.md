# 1245: Warn when bsb.kept runs on the memory store

- Status: accepted
- Date: 2026-11-25

## Context

`bsb.kept()` defaults to `memoryKeptStore()`. With one process that is correct,
but on Vercel or any multi-instance host each instance fills and expires its own
copy: a second instance misses what the first kept, and `updateTag` on one
instance leaves the others stale until the entry's life ends. Nothing told the
app to pick a durable store.

## Decision

Doctor rule BS647 (warning) reports a source that calls `.kept(` while no source
sets `kept: { store }` for `createNext`, or while one sets
`store: memoryKeptStore()`. Doctor can't see the instance count, so the rule
names the condition and the two durable stores (`postgresKeptStore`,
`vercelRuntimeCacheAdapter`).

## Alternatives considered

- A runtime warning: runs in production on every cold start, and the instance
  count is no more visible there.
- Defaulting to a durable store: needs a database client the core doesn't own.

## Consequences

Apps that use `bsb.kept()` on a single instance see a warning they can ignore
through `doctor.ignore`. An env-driven store such as the sample's `keptStore()`
counts as set.
