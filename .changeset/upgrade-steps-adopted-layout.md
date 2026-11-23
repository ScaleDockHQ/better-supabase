---
"better-supabase": patch
---

Build `sql upgrade` steps with the same context as the module files, so a step reads the configured tenant column and only touches columns an adopted table has. The tasks version 7 step no longer clears `delegate_profile` on a table without that column, and the tax version 2 step keys rates on `sql.tenantColumn` instead of `tenant_id`.
