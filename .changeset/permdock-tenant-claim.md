---
'better-supabase': patch
---

The PermDock guide says that a non-default `claims.tenant` must also be set as PermDock's `rls.tenantClaim` and passed to `subjectFromSupabase` or `subjectFromSupabaseSession` as `{ tenant }`, so both packages read and write the same tenant claim.
