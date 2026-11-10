---
"better-supabase": patch
---

The trigger that freezes an issued invoice checks import mode in its `when` clause. The trigger is deferred and its function ran at commit, after an import had restored its flag, so an import of issued invoices froze every one of them (47,668 freezes, about 219 s on CentraKit's data). Run `better-supabase upgrade` and generate the migration.
