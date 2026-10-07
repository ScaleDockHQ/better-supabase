---
"better-supabase": minor
---

`sql.modules.organizations.permissions.updateRolePlatform` and `removeMemberPlatform` name platform keys, checked with `is_platform()`, that let platform staff call `update_member_role` and `remove_member` in any organization without the service role, as `updatePlatform` and `deletePlatform` do for the organization itself. The role ceiling (`can_assign`) still applies to them.
