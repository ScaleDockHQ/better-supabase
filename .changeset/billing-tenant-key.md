---
"better-supabase": minor
---

`billing_customers` gets a foreign key to the tenant table (`billing_customers_tenant_fkey`, `on delete cascade`): the organizations module's table when it is installed, or `sql.modules.billing.options.tenantKey` (`"schema.table.column"`, `false` for none). Existing rows without a tenant leave the key unvalidated, with a warning.
