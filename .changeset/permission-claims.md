---
"better-supabase": minor
---

The access token can carry the caller's permission keys. The permissions block adds `better_supabase.permission_claims(user_id, tenant)` for the access token hook, which writes them under the `permissions` claim (`claims.permissions` renames it) for the active tenant, with `permissions_truncated` when they don't fit. `permissionsOf(session, tenant)` reads them back, and `permissionsAuthorizer({ permissions, load })` from `better-supabase/blocks/permissions` decides route, action and resource checks from the claim, calling `load` once per request only when the token can't answer.
