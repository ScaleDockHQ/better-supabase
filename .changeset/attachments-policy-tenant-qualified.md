---
"better-supabase": patch
---

The attachments read and insert policies compare the subject's tenant column with the attachment's tenant. For a subject table with its own `tenant_id` column, such as `drive_nodes`, the policy text compared the column with itself, so the subject check passed for any tenant. The policies now qualify the attachment's columns. Run `better-supabase upgrade` and apply the migration it plans.
