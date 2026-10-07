---
"better-supabase": minor
---

Under the `permdock` model, a platform invitation resolves its role only among platform roles: `sql.modules.invitations.options.platformRoles.through.where` is a condition on the roles row (`"{row}.scope = 'system'"`), checked when inviting and again at accept, and a tenant role's id or key is refused with `INVITATION_ROLE_UNKNOWN`. Before, the role was looked up across the whole roles table, so a tenant role could be granted as a platform role. Breaking: when `through.table` is also `sql.modules.tenant.options.roleThrough`'s table, `through.where` is now required.
