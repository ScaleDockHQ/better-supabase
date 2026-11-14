# 0952: Raise the bundle baselines for the G7 list surface

- Status: accepted
- Date: 2026-11-14

## Context

The `guests`, `dispatch`, `incidents`, `approvals`, `assets`, `cases` and
`deadlines` blocks now declare their list surface and ship `entityList` with
their clients (ADR 0951). Each block entry in `tests/bundle/baseline.json`
grows by the same amount as the blocks in ADR 0940, and `./blocks/service`,
which bundles them, grows with them.

## Decision

Raise the eight entries to the sizes the CI bundle job measured:

| Entry                | Before (B gzip) | After (B gzip) |
| -------------------- | --------------- | -------------- |
| `./blocks/approvals` | 34426           | 36957          |
| `./blocks/assets`    | 39259           | 41714          |
| `./blocks/cases`     | 36710           | 39553          |
| `./blocks/deadlines` | 36876           | 39366          |
| `./blocks/dispatch`  | 40121           | 43005          |
| `./blocks/guests`    | 32852           | 35212          |
| `./blocks/incidents` | 34234           | 37287          |
| `./blocks/service`   | 89903           | 95375          |

No entry is lowered. The `./eve` entry is not part of this change; its baseline
comes from ADR 1022.

The server baselines of the Next.js example grow too: 285 sizes (raw, gzip or
brotli) across 240 routes, by about 2.2 KB raw each, from the seven new manifest
declarations. Each value is the one the CI next-build job measured, and no
route is lowered.
