---
"better-supabase": minor
---

`better_supabase.audit()` takes `statement => true`, which audits a table with statement-level triggers over transition tables and writes every entry of a statement in one insert. The audit module moves to version 10 and drops the previous `audit()` signature on upgrade; calls that name their arguments keep working.
