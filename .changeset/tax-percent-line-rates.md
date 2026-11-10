---
"better-supabase": patch
---

Issuing an invoice with `options.lineRates: "percent"` now writes the rate of a line's tax code to the line as a percentage. Before, `issue_invoice_tax` wrote the code's rate in basis points into the percentage column, so a `numeric(5, 2)` rate column overflowed and the invoice could not be issued.

The invoice, credit note and quote import targets convert the same way. Updating an imported document with `update: "apply"` wrote a line's `taxRateBps` into the percentage column as is, and resolving an imported line's tax code compared the code's basis points with the line's percentage, so no code matched.
