---
"better-supabase": patch
---

Doctor BS213 no longer flags a single-column primary key, or a tenant column that every write policy pins to `better_supabase.current_tenant_id()` without an `or`, because neither lets a caller grant itself access. A column the authorization provider lists in `decidingColumns` is still flagged.
