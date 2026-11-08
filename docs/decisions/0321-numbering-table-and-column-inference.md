# 0321: Infer the numbering table and column

## Status

Accepted

## Context

A numbering entity had to repeat `table`, `column` and `tenantColumn`, although `config.subjects` already names the table and its tenant column.

## Decision

`column` defaults to `number` when `table` is set. An entity that sets only `column` takes the table of the subject whose key equals the entity name. An entity with neither stays a counter without a trigger, as before, so no existing valid config changes its output.

## Consequences

Configs shrink to `{ period, format }` for entities that follow the convention. A `column` with no table and no subject is an error.
