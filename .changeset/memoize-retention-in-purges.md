---
"better-supabase": minor
---

Every purge asks the retention and legal-hold tables once per tenant and statement instead of once per row, through the new `retention_for_memo` and `is_held_memo`. `purge_outbox` on 100,000 expired events takes 540 ms instead of 2,343 ms. A hold or policy changed between two statements still applies. Run `better-supabase upgrade` and generate the migration.
