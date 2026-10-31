---
"better-supabase": minor
---

Add payment terms, dunning runs and credit blocks to `contacts` and `invoices`. `savePaymentTerm`
and `paymentTerms` manage terms with due days, an early-payment discount and a credit restriction
whose tax is computed on the reduced amount. Invoices copy the party's terms and store
`discount_due_on` and `discount_amount_early` when issued. Customers get `creditBlock` (`none`,
`soft` or `hard`), a `language` and `setDeliveryPreferences`. Dunning levels take a `textKey`,
`runDunning` records runs you read with `dunningRuns`, `dunningRunItems` and `dunningHistory`, and
`handOverToCollection` hands invoices to a collection agency (`invoice.collection_started`).
Payment terms and delivery preferences are import targets.

Breaking: `payment_terms_days` and `paymentTermsDays` on companies and people are replaced by
`customer_terms_id` and `supplier_terms_id`. The 0.46 to 0.47 guide has the data step, and the
codemod lists the old names.
