---
"better-supabase": minor
---

Gate a read set entry on a permission with `s.when(auth.can("customer.read"), entry)`. The compiled function checks `better_supabase.can`, a refused entry is `null`, and the batch path checks each gate once. `ReadSetGate` is a new type export.
