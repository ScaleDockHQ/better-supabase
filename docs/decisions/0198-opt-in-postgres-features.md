# 0198: Postgres features are opt-in options on existing blocks

- Status: accepted
- Date: 2026-11-01

## Context

Postgres can keep several guarantees that blocks otherwise check in
TypeScript: full text search columns, non-overlapping ranges and partitioned
append-only tables. Adopters' tables may already hold data that breaks a new
constraint.

## Decision

Each feature is a block option with a default of `false`: `searchColumn`
(stored `search_tsv` tsvector with a GIN index, also the `@bsb search` tag for
app tables), `noOverlap` (btree_gist exclusion constraints, added only when
missing) and `partitioned` (monthly partitions through the shared helper of
ADR 0038). The doctor rule BS360 flags secret-named columns outside Vault.

## Alternatives considered

Turning the constraints on for everyone: a migration would fail on data that
already overlaps.

## Consequences

Generated SQL is unchanged until an option is switched on. Deferred parts are
listed in ADR 0197.
