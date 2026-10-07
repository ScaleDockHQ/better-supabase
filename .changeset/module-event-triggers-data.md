---
"better-supabase": minor
---

The data files of modules that create event triggers (`audit` with `bs_audit_forget_dropped`, `ensure-rls` with `bs_ensure_rls`) repeat them, so the `better-supabase sql data` migration creates them even when `supabase db schema declarative sync -s <schemas>` left them out of the schema migration, since event triggers belong to no schema. Doctor's new BS323 warns about a module event trigger that the live database lacks or, without a database, that no migration creates. `moduleEventTriggers(names)` from `better-supabase/sql` lists the event triggers of a set of modules.
