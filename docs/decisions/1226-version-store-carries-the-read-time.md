# 1226: Keep the read time next to each version in the shared version store

- Status: accepted
- Date: 2026-11-23

## Context

`createVersionCache` in `src/server/authz-versions.ts` reads a shared
`VersionStore` (Redis, Vercel Runtime Cache) on a local miss. `get` returned a
bare number, so the cache dated the value at the time of the lookup. With a
store that never expires, every instance that missed locally trusted a version
of any age for another `maxStaleMs`, and the next miss after that did the same.
`maxStaleMs` then bounded nothing when an eviction broadcast was lost. An
authorization library's own version cache can read a store of the same shape
and has the same gap.

## Decision

`VersionStore.get` returns `{ version, at }` and `set(userId, version, at)` takes
the time the version was read from the database, in epoch milliseconds. The
cache counts `maxStaleMs` from `at`: a stored version older than that is a miss
and is not remembered, and a value without a finite `version` and `at` is a miss.
A read dated in the future (another instance's clock) is capped at now. `seed`
writes `at` as now when its version wins, and keeps the cached entry's `at` when
a higher cached version wins. A provider library that uses the same shape can
share one store object with better-supabase. `VersionStoreEntry` is exported from
`better-supabase/server`.

## Alternatives considered

- Ask the store to expire keys after `maxStaleMs`. Not every store expires keys
  (a `Map`, Runtime Cache tags), and the cache could not check it.
- Keep `get` returning a number and store `{ version, at }` as an encoded string.
  It hides the contract in a format each store would have to parse.

## Consequences

A store written for 0.84 no longer type-checks, and at runtime its bare numbers
are misses, so it falls back to the live read instead of trusting a stale
version. The 0.84 to 0.85 guide shows the new shape.
