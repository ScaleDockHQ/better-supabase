---
"better-supabase": patch
---

Doctor BS213 counts the authorization provider's `idsWith` and `memberIds` helpers as tenant pins, next to `tenant_ids_with` and `member_organization_ids`. A write policy with an `or` still pins the tenant column when each branch pins it or writes a null tenant under a platform check, such as `(org_id in (select ids_organization('notes.create'))) or (org_id is null and (select is_platform('platform.notes.manage')))`. A column every insert policy pins to the caller, `created_by = (select auth.uid())`, no longer counts on insert.
