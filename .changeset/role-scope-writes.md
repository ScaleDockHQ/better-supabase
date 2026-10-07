---
"better-supabase": minor
---

`roleThrough.where` and `platformRoles.through.where` now hold for direct writes too. With `sql.modules.tenant.options.roleThrough.where`, the tenant module puts a `bs_role_scope` trigger on the adopted memberships table, and with `sql.modules.invitations.options.platformRoles.through.where` the invitations module puts one on `platformRoles.table`. An insert or role update that stores a role outside the condition fails with `MEMBERSHIP_ROLE_SCOPE` or `PLATFORM_ROLE_SCOPE` (SQLSTATE `23514`), whoever writes it: a client policy, the service role or an admin connection. Before, the condition only limited the roles the module functions resolved, so apps kept their own scope trigger. Breaking: a write that stored such a role now fails; rows already stored are not checked until they change.
