---
"better-supabase": patch
---

The organizations, invitations, SSO and waitlist modules resolve a role given by key within the tenant when the roles table holds tenant custom roles: `sql.modules.tenant.options.roleThrough.tenant`, or `sql.modules.access.columns.roles.tenant` under the catalog model, names the tenant column. A key that several tenants use then resolves to the tenant's own role (shared roles without a tenant still match), instead of another tenant's, and another tenant's role id is unknown.
