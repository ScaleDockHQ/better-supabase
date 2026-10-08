---
"better-supabase": minor
---

`sql.modules.access.functions.canAssignFor` (a template with `{user}`, `{tenant}` and `{role}`) defines `can_assign_as` under the provider and custom models, which an invitation accept uses to check the inviter again. Under the provider model it defaults to the authorization provider's `canAssignFor`, so an invitation to a tenant custom role is no longer refused with `INVITATION_INVITER_REVOKED`.
