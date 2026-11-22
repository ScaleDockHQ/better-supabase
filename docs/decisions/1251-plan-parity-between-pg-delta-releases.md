# 1251: Compare the CLI's pg-delta with the pinned one on a stack

- Status: accepted
- Date: 2026-11-22

## Context

`db diff` plans with the pg-delta better-supabase pins (alpha.61), and the
Supabase CLI 3.2.0 plans `declarative sync` with the release it bundles
(alpha.60). The CLI's copy lives inside its binary, so it cannot be loaded as a
library. A project that diffs with both gets two plans, and a difference in
statements or order is a regression in one of the releases, not in the schema.

## Decision

`tests/validation-declarative/src/plan-parity.test.ts` plans the project's
schema files twice against the same local stack with the same driver
(`provisionCoLocatedShadow` and `planSchemaFiles` with the Supabase profile):
once with `pg-delta-previous`, a dev dependency alias for
`@supabase/pg-delta@1.0.0-alpha.60`, and once with the pinned alpha.61. It
compares the statements without comments, layout or case, in order. It runs
with `PLAN_PARITY=1` because it needs a started stack with the migrations
applied. The alias moves to the release the CLI bundles when the CLI changes.
The first run planned 25 statements under both releases.

The alias is a month old, so it passes `minimumReleaseAge`.

## Consequences

A pg-delta bump shows a plan change before users do. The test compares the
library driver under two releases, so a difference between the CLI's own
driver and `db diff --in-stack` (the stack's baseline privileges, for one) is
outside it.
