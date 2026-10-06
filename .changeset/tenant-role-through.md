---
"better-supabase": minor
---

The `tenant` module reads membership roles through a roles table: `sql.modules.tenant.options.roleThrough: { table, id, column }` for an adopted memberships table whose role column holds a role id. Every access model then compares role names, the organizations and invitations modules store the id and refuse unknown roles, and `can_assign` receives the name. Under the `permdock` model, `sql add` takes the lookup from the manifest's `through` membership role.
