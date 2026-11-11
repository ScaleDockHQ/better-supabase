---
"better-supabase": patch
---

The pgTAP helper `tests.age_import_run` is a plpgsql function, so the pgtap module loads without the imports block installed.
