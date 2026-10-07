---
"better-supabase": patch
---

`permdockVerifier` narrows a personal key limited to one tenant with the credential's `tenant` field instead of writing the tenant as `ids` on every permission. PermDock reads `ids` as ids of the permission's own resource, so every check of such a key was denied; it reads `tenant` on user credentials (from the PermDock release that adds it) as a narrowing of the owner's memberships to that tenant.
