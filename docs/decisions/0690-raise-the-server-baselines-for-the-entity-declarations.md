# 0690: Raise the server baselines for the entity declarations

- Status: accepted
- Date: 2026-11-12

## Context

Every block manifest now declares its entities (ADR 0689). `betterSupabase`
registers every installed block, so the declarations land in the server chunk that
each `(app)` route shares. `tests/next-build` fails when a server route grows
past its baseline, and the update script only lowers one (ADR 0683, 0684).

## Decision

Reset `server-baseline.json` to the measured numbers of a fresh `next build`, by
emptying the file and running the update (ADR 0688 did the same).

| Baseline                               | Routes            | Change                                           |
| -------------------------------------- | ----------------- | ------------------------------------------------ |
| Server chunks (`server-baseline.json`) | 346 route entries | median +3,807 B gzip, at most +3,832 B per route |
| First load (`baseline.json`)           | unchanged         | the declarations are server-only                 |

## Alternatives considered

Keeping the declarations out of the manifest object (a separate module the
generators read) would avoid the growth, but then the registry, the matrix and
the checks would load two files per block and could drift apart. The growth is
about 1 percent of a route's server chunk.

## Consequences

Later lanes that add fields to `entities` grow the server chunk again and reset
the baseline in their own PR. Revisit if the declarations grow past the manifest's
other fields; a generated, tree-shakable index would then be the next step.
