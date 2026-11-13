# 0800: Raise the server baselines for the permission declarations

- Status: accepted
- Date: 2026-11-13

## Context

Six block manifests now declare `entities.<key>.permissions` (ADR 0799). The
manifests are part of the server chunk each `(app)` route shares, so the
declarations grow it. `tests/next-build` fails when a server route grows past
its baseline, and the update script only lowers one (ADR 0690).

## Decision

Reset `server-baseline.json` to the measured numbers of a fresh `next build`, by
emptying the file and running the update.

| Baseline                               | Routes            | Change                                       |
| -------------------------------------- | ----------------- | -------------------------------------------- |
| Server chunks (`server-baseline.json`) | 346 route entries | median +171 B gzip, at most +190 B per route |
| First load (`baseline.json`)           | unchanged         | the declarations are server-only             |

## Alternatives considered

Keeping the declarations in a separate module that only `gen` reads would avoid
the growth, but the manifest is where the other entity fields live and where the
conformance test reads them. The growth is about 0.05 percent of a route's
server chunk.

## Consequences

Each block that declares more keys grows the chunk by a similar amount. The
`permissions` of every block together stay a small share of the manifests.
