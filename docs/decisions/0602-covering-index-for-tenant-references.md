# 0602: Index tenant references on the foreign key's columns

- Status: accepted
- Date: 2026-11-10
- Amends: 0320

## Context

`tenantKeysSql` writes a reference between two tenant-scoped app tables as a foreign key on
`(tenant, column)` to the target's `(tenant, id)`. `indexesSql` still indexed only `(column)`.
Postgres needs an index on the referencing columns for deletes on the target and for joins,
and the Performance Advisor reported four such keys on `better-supabase-cloud`. The fixture's
`tasks_project_id_fkey` on `(organization_id, project_id)` had the same gap.

## Decision

For a column in `tenantReferences`, `indexesSql` writes `(column, tenant)`. The column leads, so
a lookup by the column alone uses it too. References to blocks or `auth.users` keep `(column)`.
The fixture's tasks table gets the same index by hand.

## Consequences

The index name changes (`<table>_<column>_<tenant>_idx`), so the next diff drops the old one. A
library check of the fixture's foreign keys found no other key without a leading index.
Block modules were checked the same way (none unindexed).
