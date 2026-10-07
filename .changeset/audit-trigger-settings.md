---
"better-supabase": minor
---

Audit registrations are declarative. `better_supabase.audit(...)` keeps a table's settings (`ignore`, `redact`, key columns, event naming, tenant and label columns) on its `bs_audit` trigger as the JSON argument of `audit_row_change`, instead of a row in `better_supabase.audited_tables`. A call in a schema file no longer leaves rows that pg-delta refuses, the generated migration carries the trigger with its settings, and apps need no data migration for registrations. A static `create trigger bs_audit ... execute function better_supabase.audit_row_change('{...}')` works the same way, and `sql sync` writes its pgTAP file too. `audit_settings(table)` returns the settings, and `audit_schema` skips tables that already have the trigger. Tables registered earlier keep working from their `audited_tables` rows until `audit()` runs for them again.
