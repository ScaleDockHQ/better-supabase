---
"better-supabase": minor
---

`sql.modules.access.functions.canAssignFor` (a template with `{user}`, `{tenant}` and `{role}`) defines `can_assign_as` under the permdock and custom models, which an invitation accept uses to check the inviter again. Under the permdock model it defaults to PermDock's `permdock_can_assign_any_for(user, role, tenant, '<scope>', tenant::text)` when the manifest lists that helper, so an invitation to a tenant custom role is no longer refused with `INVITATION_INVITER_REVOKED`; `permdock_can_assign_for`, which knows only the declared roles, stays the fallback. The accept also checks it when PermDock's other `_for` helpers are missing.
