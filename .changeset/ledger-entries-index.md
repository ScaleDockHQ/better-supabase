---
"better-supabase": minor
---

Ledger entries store the transaction's effective time and are indexed by tenant and that time. `get_many` reads the entries whose ids you pass.
