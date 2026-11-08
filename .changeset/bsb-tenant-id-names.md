---
"better-supabase": minor
---

Every block table names its tenant column `tenant_id` where 63 used `organization_id`. Run `better-supabase codemod naming` to write the migration that renames the columns of an installed app, then `upgrade`; no data moves. Apps that adopt their own tables keep their column names and map `tenant` in `columns`. `memberships.organization_id`, the default tenant column of an app table and the JSON keys of the SQL API stay.

| Old                                                                                                        | New         |
| ---------------------------------------------------------------------------------------------------------- | ----------- |
| `organization_id` on `audit_events`, `outbox_events`, `api_keys`, `invitations` and the other block tables | `tenant_id` |
