---
"better-supabase": minor
---

Under the provider access model, `member_organization_ids()`, `has_organization_role()` and `organization_member_role()` read membership from the provider's `memberIds` and `memberIdsFor` templates, so a user the provider no longer lists stops counting as a member. Doctor rule BS334 (info) reports app policies and functions that still call them and points at `tenant_ids_with` or `member_can`.
