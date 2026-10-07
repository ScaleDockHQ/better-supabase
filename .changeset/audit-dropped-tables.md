---
"better-supabase": patch
---

A dropped audited table no longer leaves its registration behind. The audit module installs a `sql_drop` event trigger (`bs_audit_forget_dropped`) that removes the table's row from `better_supabase.audited_tables`, `unaudit(text)` accepts a table that no longer exists and clears the registrations of dropped tables, and `sql sync` treats a later `drop table` in a migration like `unaudit`, so it removes the table's pgTAP file instead of writing a `has_trigger` test that fails. Install the audit module as `postgres`, which supautils lets create event triggers.
