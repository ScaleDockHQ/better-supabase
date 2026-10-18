---
"better-supabase": minor
---

`blocks.tenant.options.sameTenant` takes `{ auto: true, entries? }`. `sql sync` then derives an entry for every single-column foreign key between two tables with the tenant column, from `references`, `foreign key` constraints and `alter table ... add constraint` in the schema files. A listed entry for the same column wins, and a derived entry renders the same trigger as the listed one. The list form is unchanged. Doctor's new BS340 lists tenant foreign keys without a `bs_same_tenant_<column>` trigger. `better-supabase/sql` exports `sameTenantLayout`, `sameTenantColumn` and `sameTenantTrigger`.
