---
"better-supabase": minor
---

The `invoices` block now lists open items per customer and supplier with ageing, and
`allocatePayment` spreads one payment over several documents (partial, over and under payment, and
the early-payment discount, posted through accounting). `unallocatePayment` reverses it. Purchase
bills get approval levels by amount with an approver per legal entity (`approvePurchaseInvoice`,
`approvalStatus`, the `invoices.approve` key). The `banking` block builds payment batches from
approved open supplier bills, exports them as SEPA credit transfers (pain.001.001.09) and closes
them when the bank debit is matched. The `open_item` import target loads opening lists with their
original dates. Run `better-supabase upgrade` and apply the new migrations.
