# 0266: Copy mutation rows on first read

- Status: accepted
- Date: 2026-11-07
- Amends: 0234

## Context

`afterMutation` deep-cloned each returned row for any `mutation` listener, and
the Next.js adapter attaches the cache listener by default, which reads only the
primary keys. Every write paid the clone.

## Decision

The `rows` of the `mutation` notice are a getter: the copy is made on the first
read and shared with the plugins' event. `keysOf` reads the executor's rows
directly, and `cacheTargetOf` reads `notice.keys` before `notice.rows`, so a
write whose only listener is the cache adapter makes no copy. A listener that
awaits before reading `rows` sees the row as it is at that read, not at the
write; the executor's rows are not changed after the write returns. The plugin
event still gets its copy at once.

## Measured and not done

Server-runtime items are held to the client bundle gate, because `core` and
`blocks` ship to the browser too:

- Checking the block port wiring once per block set (a `WeakMap` over the block
  set, config and `ports`) added about 250 raw bytes to every route of the
  Next.js example, and `tests/next-build` allows no growth. It was reverted.
  The check is blocks times ports times blocks and runs per connected `db`;
  moving it out of the client chunk needs the builder split into a server-only
  module first.
- A single `resolveAuth` per render scope and a straight path in
  `server.context()` change the order of session verification and the cookie
  seam that ADR 0095 and 0117 pin. They need a fixture that counts cookie parses
  and token-memo lookups per request first.
- `AsyncResult.from` taking a promise changes a public signature used across the
  blocks.

## Consequences

The first-load JavaScript of every Next.js route drops by 39 raw and about 28
brotli bytes, and `tests/next-build/baseline.json` records it.
`tests/core/repository-methods.test.ts` asserts the row copy count for a
keys-only listener and for a rows listener.
