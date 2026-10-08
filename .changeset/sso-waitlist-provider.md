---
"better-supabase": minor
---

The `sso` and `waitlist` modules work under the `provider` and `custom` access models. `sql.modules.sso.options.roleOrder` and the new `sql.modules.waitlist.options.roles` list the roles they may assign when the roles are not in the config, and role ids go through `roleThrough`. Setting a domain's `auto_join_role` and creating an invite code with a role now also need `can_assign(tenant, role)` for the caller (`SSO_ROLE_FORBIDDEN`, `WAITLIST_ROLE_FORBIDDEN`), which is the provider's `canAssign` under the provider model; the service role and platform staff skip it.
