---
"better-supabase": minor
---

The audit block's row triggers on block tables are static `create constraint trigger bsb_audit` statements in each block's schema file, whatever the install order, so a schema diff keeps them. Run `better-supabase upgrade` and then your SQL workflow's sync. Doctor and the audit test file read the deferrable trigger form.
