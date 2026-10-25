# 0106: Plan migrations with pg-delta's library plan

- Status: accepted
- Date: 2026-10-25

## Context

`db schema declarative sync` runs pg-delta with renames off and reports no data loss. The CLI's
`db diff` copies the database with `pg_dump` (ADR 0059) to build a shadow.

## Decision

- The CLI loads `@supabase/pg-delta` (an optional peer that only the CLI loads, pinned near the
  Supabase CLI's bundled version) and uses its library plan: `renameCandidates` and
  `classifyPlanHazards`.
- Renames come from `-- bsb: rename` steps in the edit log or from a prompt over the candidates.
- A destructive action is blocked unless the user passes `--allow-data-loss`.
- `provisionCoLocatedShadow` replaces the `pg_dump` copy.
- The cloud deploy planner uses the same plan.

## Alternatives considered

- Keep shelling out to the Supabase CLI: no rename or hazard data.

## Consequences

The pin goes in "Pre-release pins" until pg-delta ships a stable release.
