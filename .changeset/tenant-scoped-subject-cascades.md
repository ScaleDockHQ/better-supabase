---
"better-supabase": patch
---

Deleting a subject row deletes its attachments, reactions, reviews and conversation rows through the tenant-led index instead of scanning the table: the cascade trigger passes the subject row's tenant. Run `better-supabase upgrade` and generate the migration.
