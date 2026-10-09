---
"better-supabase": minor
---

The tenant module keeps references inside one tenant and reads membership roles through a roles table.

- `sql.modules.tenant.options.sameTenant` entries add a trigger that fails a write referencing another tenant's row with `TENANT_MISMATCH`, also through `match` and `through` columns.
- `options.roleThrough: { table, id, column, where?, tenant? }` reads role names when memberships store role ids, taken from the provider's `roleSources` under the `provider` model. A `bs_role_scope` trigger refuses roles outside `where` on direct writes (`MEMBERSHIP_ROLE_SCOPE`), and doctor BS324 reports a shared roles table without `where`.
