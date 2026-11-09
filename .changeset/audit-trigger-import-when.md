---
"better-supabase": minor
---

Row audit triggers skip the rows of an import that runs with `imports.audit: summary` before the audit function starts. The trigger has a `when` clause that reads the import session, so a 20-row insert and update batch now starts `audit_row_change` zero times instead of once per row. A user who sets the flag without an import session is still audited.

`better-supabase upgrade` rewrites every module with block-table audit triggers, and the next schema migration drops and creates each `bsb_audit` trigger. No data migration is needed.
