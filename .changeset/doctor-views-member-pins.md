---
"better-supabase": patch
---

`doctor` no longer reports BS204 for a view's tenant column, since a query on a view uses the indexes of its tables. BS213 now counts a tenant column that every write policy holds to `column in (select better_supabase.member_organization_ids())` as pinned, the same as `tenant_ids_with(...)`, so app tables that are subjects no longer warn.
