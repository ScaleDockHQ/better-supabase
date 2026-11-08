---
"better-supabase": minor
---

`better-supabase codemod server-imports` moves the account, CSV and rate-limit helpers that `better-supabase/server` no longer exports to `better-supabase/server/accounts`, `better-supabase/server/csv` and `better-supabase/server/rate-limit`. Names that stayed on `server` keep their import, and an aliased or type-only import keeps its form.
