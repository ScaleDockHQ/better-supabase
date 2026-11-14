# 0940: Raise the bundle baselines for the G6 list surface

- Status: accepted
- Date: 2026-11-14

## Context

The `domains`, `imports`, `access-requests` and `forms` blocks now declare their
list surface and ship `entityList` with their clients (ADR 0749, 0939). Each
block entry in `tests/bundle/baseline.json` grows by the same amount as the
blocks in ADR 0790.

## Decision

Raise the four entries to the sizes the CI bundle job measured:

| Entry                      | Before (B gzip) | After (B gzip) |
| -------------------------- | --------------- | -------------- |
| `./blocks/domains`         | 30150           | 33256          |
| `./blocks/imports`         | 34901           | 38003          |
| `./blocks/access-requests` | 29679           | 32911          |
| `./blocks/forms`           | 39651           | 42843          |

The next-build baselines grow too: the raw First Load JS of 246 routes by about
100 B each, and the raw server chunks of 273 routes by about 0.8 to 1.4 KB each, from
the four new manifest declarations. Each value is the one the CI next-build job
measured, and no route is lowered. The default type profile's `ts71Mapper`
program grows from 16767 to 18876 types (the mapped list types of the four
blocks), and its baseline takes the CI-measured value.

## Alternatives considered

Keeping `entityList` out of each block's client would avoid the growth, but
each block would then keep its own paging code, which is what the shared
function removes.

## Consequences

Each further block that moves adds about 3 KB gzip to its own entry.
