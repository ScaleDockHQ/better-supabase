---
"better-supabase": minor
---

Under the `provider` access model, `sql.modules.access.disabled` defaults to the authorization provider's `suspension` rows for users and tenants, so disabled tenants and users match the provider's rule without setting the same columns twice. `disabled.tenant` and `disabled.user` also accept an active-row shape (`{ table, id, disabledAt, status, active }`), where a missing row counts as disabled. An explicit setting still wins per subject.
