# 0641: Bound the version cache and share the block builder per db

- Status: accepted
- Date: 2026-11-10
- Amends: 0096

## Context

The performance audit left three request-path leads open under `p2c-core-rest`. `createVersionCache`
kept one entry per user for the life of the process and only checked age on read, so a long-lived
server grew with every user it had seen. `BlockSet.client(db, key)` built a new block builder, and
checked and wired the whole port graph, on every call. Gates and function specs in a read set run in
sequence, and the audit also lists an API key on `ctx.auth`, `observedFetch`, a context factory and
batch block reads.

## Decision

- `createVersionCache` takes `maxEntries` (default 10,000). The in-process map is an LRU: a read or
  a write moves the user to the end, and the oldest user goes when the map is full. The shared
  `store` still holds the version, so an evicted user costs one store read.
- `BlockSet.client(db, key)` without options shares one builder per `db` in a `WeakMap`, so the port
  graph is wired once and each block client is built once. Calls with options still build their own.
- Not built here: awaiting gates and function specs together lives in `core/define-runtime.ts`
  (read sets, owned by another workstream); the context factory, route kits, API key on `ctx.auth`,
  `observedFetch`, batch block reads, the data-changing result mapper, tenant from the URL, RPC
  payload cache tags and the two controllers stay open in `p5b-runtime` and `p5b-next-rest`.

## Alternatives considered

- A time-only sweep for the version cache: it bounds age, not size under a burst of users.
- Sharing the builder when options are given: options such as `transport` or `hooks` change the
  built clients, so only the empty case is safe.

## Consequences

Memory of the version cache is bounded by `maxEntries`. Repeated `client(db, key)` calls skip the
builder setup. No public export changes; `maxEntries` is an optional field.
