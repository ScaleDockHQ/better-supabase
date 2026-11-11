# 0676: Raise the next-build baselines after lazy relation targets

- Status: accepted
- Date: 2026-11-11
- Amends: 0674

## Context

With `gen.serverTables: "lazy"`, a repository method loaded only its own table, so an include, a
nested include, a relation filter, a count or an `orderBy` across a relation failed with
`unknown table` in a fresh process. The fix wraps the repository methods of a lazy schema so they
load every table their arguments reach through relations before the query is built. That code sits
in the shared db runtime, which every route of the Next.js example ships.

A build of `main` at `bd8cb9077` passed every guard in `tests/next-build`. The same build with the
fix failed two guards. The update script never raises a baseline, so the numbers move by hand.

## Decision

The baselines move to the values measured with the fix, and no guard or slack changes.

| Guard                                 | Routes | Growth                                                            |
| ------------------------------------- | ------ | ----------------------------------------------------------------- |
| First Load JS (raw)                   | 113    | +836 to +951 bytes per route                                      |
| First Load JS, shop order page (gzip) | 1      | +1084 bytes                                                       |
| Server chunks (raw)                   | 166    | +831 to +836 bytes per route                                      |
| Server chunks, two well-known routes  | 2      | +653 bytes gzip on the OAuth metadata route, +970 brotli on flags |

Every other baseline stays as it is.

## Consequences

Apps that list their tables pay the few hundred bytes of the wrapper code without running it. Moving
the lazy path behind its own entry would win them back, at the cost of a second runtime shape.
