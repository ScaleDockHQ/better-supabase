# 0750: Raise the server baselines for the list surface

- Status: accepted
- Date: 2026-11-13

## Context

The nine blocks that page now declare `sorts`, `facets` and `filters` in their
manifests (ADR 0749). `betterSupabase` registers every installed block, so the
declarations land in the server chunk that each `(app)` route shares, as the
entity declarations did (ADR 0690). `tests/next-build` fails when a server
route grows past its baseline, and the update script only lowers one.

## Decision

Reset `server-baseline.json` to the measured numbers of a fresh `next build`, by
emptying the file and running the update.

Measured change per route against the baseline on main, in bytes, over the 346 routes:

| Size | Smallest | Median | Largest |
| ---- | -------- | ------ | ------- |
| raw | -1630 | 3731 | 3773 |
| gzip | -41 | 2019 | 2052 |
| brotli | -184 | 1726 | 1889 |

## Alternatives considered

Keeping the names out of the manifests (read only by the SQL) would avoid the
growth, but then the client could not check a sort, a filter or a facet before
the call, and the rollout lanes would have no declaration to generate pages from.

## Consequences

Each rollout lane (G2 to G5) grows the chunk again as it declares its blocks'
surfaces and resets the baseline in its own PR. Revisit if the declarations grow
past the manifest's other fields.
