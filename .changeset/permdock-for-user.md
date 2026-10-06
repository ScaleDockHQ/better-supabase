---
"better-supabase": minor
---

The `permdock` access model answers for other users through PermDock's helpers for a named user (`permdock_has_for`, `permitted_<scope>_ids_for`, `permdock_can_assign_for`): `sql add` uses those the manifest lists, and `sql.modules.access.permdock.forUser: true` declares them otherwise. With them, `can_user()` and `member_can()` answer for any user, the invitations module checks the inviter's permission and role assignment again at accept, and the notifications module filters recipients by their read permission. The access docs list which module checks change next to PermDock.
