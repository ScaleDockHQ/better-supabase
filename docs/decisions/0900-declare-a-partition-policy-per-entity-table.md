# 0900: Declare a partition policy per entity table

- Status: accepted
- Date: 2026-11-14

## Context

Archiving and partitioning exist for the audit log, outbox and notifications
(ADR 0038, 0601). Entity tables have no declared policy (EX-1325), so nothing says
which tables grow without bound.

## Decision

`EntitySurface.partition` is `{ by, every, archive? }`: the timestamp column,
`month`, `quarter` or `year`, and `detach` or `drop` for a partition past its
retention class. `field_history` declares monthly partitions by `changedAt`,
matching its existing partitioned option. The conformance test checks the shape.

## Alternatives considered

A `partition` option in each block's SQL options only: it stays invisible to the
doctor and the generators.

## Consequences

The doctor and the generators can read which tables grow without bound. The
declaration does not create partitions; the SQL options still do.
