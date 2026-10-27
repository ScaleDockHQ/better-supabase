---
"better-supabase": minor
---

The permissions block's catalog model gains `list_roles(tenant)` and `set_permission_override(tenant, role, permission, granted)`, and the permissions client gains `roles()` and `setOverride()`. They list the tenant roles with their default and effective keys, and grant, deny or clear one key for a role in one tenant. Listing needs `members.read`, changing needs the new `roles.manage` key; a member changes only roles they could assign and keys they hold.
