---
"better-supabase": minor
---

The `permissions` claim can carry a bitset per tenant (`{ h, b }`, about 60 bytes for 300 keys) instead of the key list. The built-in roles and catalog models generate `better_supabase.permission_claims_bitset(user, tenant)` for the access token hook, `permissionCatalog` in `better-supabase/claims` builds the catalog that expands it, and `permissionsOf`, `permissionsAuthorizer` and `permissionsShareKey` read it. A catalog that differs from the hook's returns `undefined`, so the caller reads `my_permissions()`.

`gen` also writes `permissionKeys`, the catalog key list, to `permission-scopes.ts`.
