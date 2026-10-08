---
"better-supabase": patch
---

The organizations module's `suspendMember` permission now defaults to the configured `removeMember` key instead of the fixed `members.remove`, as the docs describe. An app that renames `sql.modules.organizations.permissions.removeMember` (for example to `member.remove`) no longer needs to set `suspendMember` as well for `sql upgrade`, doctor and the generated `suspend_member` and `resume_member` functions to use its key. Setting `suspendMember` still overrides it.
