---
"better-supabase": minor
---

Plugins compose without holes. `timestamps()`, `actor()` and `softDelete()` refuse caller-supplied values for the columns they fill unless the call passes `{ override: true }`, and generated JSON Schema and OpenAPI documents mark those columns `readOnly`. On tenant tables, an upsert that updates on conflict needs the tenant column in its conflict target, the SQL executor guards the update with `where <tenant> = excluded.<tenant>`, a query whose includes reach a tenant table fails closed without a tenant, and numeric tenant columns compare by their text. An upsert that updates a soft-deleted row restores it.

`rules()` runs before every other plugin. `noUnboundedFindMany` skips aggregates, `maxLimit` ignores `paginate()`'s look-ahead row, `requireTenantContext` reads the same claim paths as `tenant()`, and `noSensitiveSelect` checks reads only, because writes without a `select` no longer return sensitive columns. Offset `paginate()` orders by the primary key by default. `validation()` decodes codec columns (Temporal values, `bigint`) before validating and encodes them afterwards.

Mutation events give hooks and listeners a copy of the rows, so they can't change the result (`testPlugin` checks this), and carry `intent` (`softDelete` for a delete that became an update), the affected primary `keys` when they are known, and the `tenant` that `tenant()` resolved. CloudEvents and cache invalidation use them, so soft deletes send `row.softdeleted` events and invalidate their rows. `defineReadSet` warns when query plugins scope tables its generated function reads. The audit kit keys entries by each table's primary key and reads the tenant column from `plugins.tenant.column`, and `gen` refuses a soft-delete column that isn't a timestamp.
