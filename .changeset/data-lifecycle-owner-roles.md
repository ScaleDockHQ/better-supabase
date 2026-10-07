---
"better-supabase": patch
---

`cancel_organization_deletion` checks the owner through the tenant module's `organization_member_role`, which resolves role names through `sql.modules.tenant.options.roleThrough`, instead of comparing the memberships table's role column with the owner role's name. Owners of adopted memberships that store a role id can cancel a pending deletion again.
