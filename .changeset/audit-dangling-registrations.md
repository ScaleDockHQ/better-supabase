---
"better-supabase": minor
---

The audit module's data file deletes `better_supabase.audited_tables` rows whose table no longer exists, so tables dropped before the `bs_audit_forget_dropped` event trigger was installed lose their registration in the next `better-supabase sql data` migration. Doctor's new BS322 warns about such rows on a live database while `audit` is in `sql.modules`.
