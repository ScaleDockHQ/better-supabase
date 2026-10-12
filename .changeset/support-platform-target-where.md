---
"better-supabase": patch
---

The `support-sessions` module's platform-target check honours `sql.modules.invitations.options.platformRoles.through.where` under the `provider` access model: a target counts as platform staff only through a role that matches the condition, so a roles table that mixes tenant and platform scopes no longer blocks support sessions for users who hold only tenant roles.
