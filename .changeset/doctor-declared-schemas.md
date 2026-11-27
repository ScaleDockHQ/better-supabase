---
"better-supabase": patch
---

Doctor reads the schema of a schema-qualified `authorization.tables` name even when `schemas` does not list it, so BS428 can check that table instead of reporting it missing.
