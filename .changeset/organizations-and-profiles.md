---
"better-supabase": minor
---

Organizations can suspend members, route deletion through data-lifecycle and give platform staff admin rights, and profiles store an avatar path. Run `better-supabase sql upgrade`.

- `suspend_member` and `resume_member` (`organizations.suspendMember`, `resumeMember`) keep a member's role but drop its permissions through the memberships table's `disabled_at`; they refuse the caller, the last owner and higher members. `transfer_ownership` refuses suspended or disabled new owners.
- `options.deleteMode: "lifecycle"` sends deletion through data-lifecycle's grace period, and `"none"` writes no delete function.
- `permissions.updatePlatform`, `deletePlatform`, `updateRolePlatform` and `removeMemberPlatform` let platform staff manage any organization. `options.assignmentGuard: "external"` drops the module's role guard, which now checks only client writes.
- Profiles get `avatarPath`, `usernameFrom` takes several keys with a separator, and `readPolicy: { platform }` lets staff read every profile. `reserved-slugs` takes `slugs`, `minLength` and `maxLength`.
