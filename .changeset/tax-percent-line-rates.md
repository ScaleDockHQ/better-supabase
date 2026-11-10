---
"better-supabase": patch
---

Issuing an invoice with `options.lineRates: "percent"` now writes the rate of a line's tax code to the line as a percentage. Before, `issue_invoice_tax` wrote the code's rate in basis points into the percentage column, so a `numeric(5, 2)` rate column overflowed and the invoice could not be issued.
