---
"better-supabase": minor
---

Under the `permdock` access model, `sql.modules.access.disabled` defaults to PermDock's manifest: `rls.suspension.users` for users and the tenant scope's row in `rls.suspension.scopes` for tenants, so disabled tenants and users match PermDock's suspension rule without setting the same columns twice. `disabled.tenant` and `disabled.user` also accept PermDock's active-row shape (`{ table, id, disabledAt, status, active }`), where a missing row counts as disabled. An explicit setting still wins per subject.
