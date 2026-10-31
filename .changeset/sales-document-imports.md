---
"better-supabase": minor
---

Invoices, credit notes, quotes and orders can be imported as historical documents through the
`imports` block. Each keeps its number, original dates, final status, buyer snapshot and stored
totals, and writes no events, stock movement or accounting posting. A tax or total that differs from
the computed one is reported as an item warning, and `upsertBatch` now returns `warnings`. Document
lines gain `discountAmount`, `costSource`, `locationId`, `binId` and a billing party, and
`document_totals_by_billing_party` reports totals and cost per billing party.
