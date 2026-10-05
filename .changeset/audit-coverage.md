---
"better-supabase": minor
---

Doctor reports tables without an audit trigger when the `audit` module is in `sql.kit` (BS315), with `kits.audit.options.exempt` for tables that don't need one. `sql add` and `sql sync` write a pgTAP file per table registered with `better_supabase.audit(...)`, which checks the trigger, the registered `ignore` and `redact` lists, and the entries an insert, update and delete write.
