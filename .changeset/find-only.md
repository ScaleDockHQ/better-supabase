---
"better-supabase": minor
---

Repositories get `findOnly({ where })`, the equivalent of supabase-js `maybeSingle()` for a filter without a unique key behind it. It returns the one matching row, `null` when none matches, and a `multiple_rows` error (status 409) when more than one does, where `findFirst` would return one of them. It reads at most two rows and is also available on `betterSupabase.spec` and the TanStack Query factories.
