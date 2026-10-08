---
"better-supabase": minor
---

`sql.modules.organizations.options.assignmentGuard: "external"` drops the module's role guard trigger on an adopted memberships table when another trigger, such as an authorization provider's assignment rules, already checks role changes. The module's functions still check `can_assign` before they write.
