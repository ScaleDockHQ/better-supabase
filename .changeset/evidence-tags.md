---
"better-supabase": minor
---

Three `@bsb` table tags guard evidence tables. `append-only` refuses update, delete and truncate, `function-writes` removes the Data API write privileges, and `chain` links each inserted row to the previous one with a hash. `better_supabase.verify_chain` (service role) finds a changed, removed or reordered row, and `record_chain_checkpoint` stores signed heads. The audit module is now version 12 and installs the helpers; no migration step.
