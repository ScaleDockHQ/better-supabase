---
"better-supabase": minor
---

The settings block has a `platform` scope for product-wide settings, and feature flags can be managed from an admin page.

- `defineSettings({ platform })` adds `client.platform`; each key names the permission that changes it and who reads it, and only listed keys can be written.
- `createFlagAdmin({ transport })` lists, saves and deletes flags and sets overrides for staff with `flags.manage`. `tenant_ids_with_flag(key)` is the policy form of `flag_enabled`, `createFlagsProvider` works over the Data API, and `flagContext` reads a `memberships` claim.
