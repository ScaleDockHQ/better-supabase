---
"better-supabase": minor
---

Delegated tokens are narrowed inside the access functions. A token with a `client_id`, or an `act` chain that is not a support or impersonation session, passes `member_can`, `member_can_while_deleting`, `platform_can` and `tenant_ids_with` only for the permission keys its scopes map to, through the new `better_supabase.cap_allows(permission)`. Map scopes in `sql.modules.access.scopes` or `authorization.delegation.scopes` (a scope without an entry grants the key with its own name, `["*"]` grants every key). `forContext(context, { permissions })` sets a `bs_permission_cap` claim that caps the work the same way, and a provider can map scopes at runtime, per client or from RFC 9396 `authorization_details`, with the `delegation.permissions` hook.

Breaking: an OAuth client or MCP server whose scopes map to no permission key is now refused where it used to pass with the user's roles. The 0.8 to 0.9 guide lists the mapping to add.
