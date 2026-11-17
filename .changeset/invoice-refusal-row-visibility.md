---
"better-supabase": minor
---

A refused invoice action now answers `INVOICE_FORBIDDEN` to a caller who sees the invoice through the invoices table's own select policies, not only through the `read` key, so readers whose permission has row conditions no longer get `INVOICE_NOT_FOUND`. The prelude adds `better_supabase.row_visible(rel, column, value)` for the same decision in your own functions.
