---
"better-supabase": patch
---

`update_member_role` checks the own-role rule and `can_assign` for the member's current role and for the new one itself, whatever `sql.modules.organizations.options.assignmentGuard` says. With `assignmentGuard: "external"` and a guard that checks only client writes (PermDock's assignment triggers skip `security definer` functions), an admin could demote an owner through the function; it now fails with `ORGANIZATION_ROLE_CEILING`, and a change to the caller's own role with `ORGANIZATION_SELF_ROLE`.
