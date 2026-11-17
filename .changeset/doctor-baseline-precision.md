---
"better-supabase": patch
---

Doctor reports fewer false positives: BS107 skips commands the API roles hold no privilege for, BS117 is info when `anon` holds no privilege on the table, BS204 accepts an expression index led by the tenant column, BS205 is info on an insert-only policy, and BS206 counts `union all` branches and `from helper('k') t(id)` with constant arguments as once per statement.
