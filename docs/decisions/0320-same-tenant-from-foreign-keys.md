# 0320: Check same-tenant references from the foreign keys by default

## Status

Accepted

## Context

`sameTenant` listed every reference that must stay inside one tenant. Apps repeated their foreign keys in config, and a forgotten entry left a cross-tenant reference possible. The `auto` flag already derived the entries from the schema files, but it was off unless the config said so.

## Decision

Without the option, the memberships module derives the entries from the declared foreign keys. A list adds entries (a listed `table.column` wins over the derived one), `false` writes none, and `{ auto: false, entries }` keeps the old listed-only form. A key is skipped when it includes the tenant column or when a composite key on the table pairs the column with the tenant column on both sides. A render that carries no schema files (outside `upgrade`) derives nothing.

## Consequences

Existing apps get more triggers on the next `upgrade`. Config keeps only the exceptions that need `match`, `through` or `where`.
