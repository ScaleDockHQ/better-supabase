---
"better-supabase": minor
---

A credit note import reads `resolved.original` as well as `originalId` and the original number. A negative invoice total becomes a credit note when that original resolves. Without an original it stays an invoice and returns `IMPORT_CREDIT_WITHOUT_ORIGINAL`. A row settlement with no original posts nothing and returns the same warning.
