---
"better-supabase": minor
---

`inventory.levels` reads the stock levels of a list of variants in one call, and `inventory.movements` pages the ledger movements by variant, location, bin, lot or document. `releaseAllocation` and `transferAllocation` take an optional `quantity`: a release shrinks the allocation and a transfer splits it, moving held stock first into a new allocation on the new document. The SQL functions `release_allocation` and `transfer_allocation` take the same optional `quantity`.
