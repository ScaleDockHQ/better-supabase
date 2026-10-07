---
"better-supabase": minor
---

`sql.modules.tenant.options.roleThrough.where` names the tenant roles in a roles table that holds other roles too: a condition on the roles row (`"{row}.scope = 'organization'"`) that every membership role lookup keeps to. Organization invitations, `update_invitation` and accept refuse a role outside it with `INVITATION_ROLE_UNKNOWN`, `update_member_role` and ownership transfer with `ORGANIZATION_ROLE_UNKNOWN`, and SSO and waitlist joins resolve only those roles. Before, a platform role's id or key in the shared table resolved as a tenant role. Breaking: under the `permdock` model, when `roleThrough`'s table is also `sql.modules.invitations.options.platformRoles.through`'s, `where` is now required, and the new doctor rule BS324 (error) reports the side of a shared roles table without it. A `roleThrough` read from PermDock's manifest has no `where`, so such a project sets `roleThrough` in the config.
