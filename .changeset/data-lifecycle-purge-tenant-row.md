---
"better-supabase": minor
---

The organization purge deletes the tenant's own row last, also for an adopted tenant table: the organizations module's table, the table `sql.modules.access.disabled.tenant` names, or `sql.modules.data-lifecycle.options.tenantRow` (`"schema.table.column"`, `false` to keep it), so no `on_organization_purge` hook is needed. A table whose delete hits a restricting foreign key or makes an `on delete set null` break a check is retried in a later pass, so apps keep their foreign keys to the tenant. The purge never deletes its own `organization_deletions` row.
