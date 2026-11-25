---
"better-supabase": minor
---

`procurement.payDueBills` and the new `banking.payBatch` run as one database call. The `pay_payment_batch` function creates the batch and posts it in one transaction, and the client writes the SEPA file from the bank accounts the call returns. A bill that needs approval now leaves no draft batch behind. The TypeScript hooks of `createPaymentBatch`, `postPaymentBatch` and `exportSepaCreditTransfer` no longer fire inside `payDueBills`; the composite's own hook does.
