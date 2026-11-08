# 0259: Exempt a class of tables from audit coverage

- Status: accepted
- Date: 2026-11-07
- Amends: 0252

## Context

BS315 lists the tables in `schemas` without an audit trigger. The audit helpers
(`audit_schema_calls`, `audit_schema`) register only tables that have the tenant
column, so a project listed each table without one by name, one `{ table, reason }`
entry per table.

## Decision

`blocks.audit.options.exempt` takes `{ class: "no-tenant-column", reason }`. It
leaves out every table in `schemas` that has no tenant column: `sql.tenantColumn`
or `<tenant>_id` for the project's tenant name. Without a reason the entry is an
error, like a bare glob. The change is in `src/cli/doctor/audit-coverage.ts` and
the `AuditExemption` type.

## Alternatives considered

Skipping those tables without an entry would let a table with a differently named
tenant column slip through unaudited. The class keeps the gap visible in the
config, with its reason.

## Consequences

A project replaces its list of untenanted tables with one entry. The rest of the
Part 4 inference (function `notNull`, notifications `on`, the settings and
`gen.json` from Standard Schema, the vector search include) is not part of this
change.
