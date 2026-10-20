# 0050: Migrations between designs re-render the app-table file

- Status: accepted
- Date: 2026-10-20

## Context

A hosted app deploys a design once and then edits it. The next deploy needs a
migration, and `diffDesigns` only classifies changes.

## Decision

`migrationBetween` accepts added tables and added columns. Because the
rendered app-table SQL is idempotent, the migration is the re-rendered file
when it differs from the base render. A breaking change, any other change kind
and any differing file outside the app-tables module are refused.

## Alternatives considered

Generating per-change DDL: more code, and it would duplicate the policies,
grants and triggers the renderer already writes. Applying every change: a
rename or retype can lose data and needs the expand and contract steps.

## Consequences

Edits that change a default, an option or a constraint are refused until a
later decision covers them. The test applies the first deploy and the
migration in PGlite, so a renderer change that breaks idempotency fails there.
