---
"better-supabase": patch
---

`better-supabase codemod naming` no longer pins a block's `tenant` column to the name that `sql.tenantColumn` already gives it. That pin wrote a `columns.<table>.tenant` entry which `upgrade` then refused.
