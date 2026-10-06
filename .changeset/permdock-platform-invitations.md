---
"better-supabase": minor
---

Platform invitations work under the `permdock` access model: `sql.modules.invitations.options.platformRoles` names the app's platform role table (with an optional `through` roles lookup and a `canAssign` template), the inviter needs `invitePlatform` through `permdock_has`, and accepting inserts the assignment. The `support-sessions` module counts a row in that table as a platform target.
