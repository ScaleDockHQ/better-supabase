# 0790: Raise the bundle baselines for the G5 list surface

- Status: accepted
- Date: 2026-11-13

## Context

The `legal-entities`, `courses` and `content` blocks now declare their list
surface and ship `entityList` with their clients (ADR 0749, 0789). Each block
entry in `tests/bundle/baseline.json` grows by the same amount as the nine
blocks in ADR 0750. `learning` re-exports `courses`, so its entry grows with it.

## Decision

Raise the four entries to the sizes the CI bundle job measured:

| Entry                     | Before (B gzip) | After (B gzip) |
| ------------------------- | --------------- | -------------- |
| `./blocks/courses`        | 47822           | 50425          |
| `./blocks/content`        | 34212           | 36817          |
| `./blocks/legal-entities` | 32140           | 34670          |
| `./blocks/learning`       | 43094           | 45818          |

## Alternatives considered

Keeping `entityList` out of each block's client would avoid the growth, but
then each block would keep its own paging code, which is what the shared
function removes.

## Consequences

The next-build server baseline is reset from CI values if its job reports
growth, as in ADR 0750. Each further block that moves adds about 2.5 KB gzip to
its own entry.
