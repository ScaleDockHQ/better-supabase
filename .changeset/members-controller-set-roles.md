---
"better-supabase": minor
---

The members controller has `setRoles({ userIds, role })`. It changes many roles in one `update_member_roles` call, shows the new role at once, puts back the roles of the members the database refused and returns `{ succeeded, failed }`. `useMembers` returns it, and the members table recipe applies its bulk role change with it instead of one `setRole` call per member. `createMembersController` now needs `updateMemberRoles` on its `client`, which `createOrganizations` already has.
