---
"better-supabase": patch
---

`better-supabase sql add` renders the named modules next to the ones `sql.modules` already lists, so a module that adapts to an installed one (billing's foreign key to the organizations table, usage quotas over entitlements) is written the same way `sql sync` writes it. It still writes only the named modules and their dependencies.
