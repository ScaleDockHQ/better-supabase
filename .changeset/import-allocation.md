---
"better-supabase": minor
---

`invoice_allocation` links an existing receipt to an invoice and moves the paid total without posting a ledger entry. `allocateExisting` is the same call from the invoices client. Row settlement still writes the paid state with no allocation.
