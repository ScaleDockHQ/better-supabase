---
"better-supabase": patch
---

`client.queries.<table>` now works for a table that a `lazyTables` client registers after it was built. Before, `queries.customers` was `undefined` for a table registered later, so `queries.customers.list(...)` threw `Cannot read properties of undefined (reading 'list')`.
