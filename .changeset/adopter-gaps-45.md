---
"better-supabase": minor
---

Adopter gaps, round 45: quotes over an app table with a fixed customer column and no list or discount totals, product ids of the column's own type, reasons on quote and payment status changes, a switch for the quote owner notification, and a text or inet IP column in an app's state machine history.

- Quotes: with `columns.quotes.companyType: null` (or `contactType: null`), the id column holds one fixed type, `options.company` (or `contact`). `create` and `update` write the id in the column's own type and refuse another type (`QUOTE_COMPANY_UNSUPPORTED`), reads return the type, and invoices' `fromQuote` carries the customer to the invoice.
- Quotes: `listTotal` and `discountTotal` may map to `null`, as on invoices; reads return the subtotal and a zero discount.
- Quotes: `withdraw(quoteId, { reason })` (SQL: `withdraw_quote(quote, actor, reason)`) and the note of `decide` go to the state machine's history as the reason.
- Quotes: `decide` without `by` or an actor leaves `decidedBy` empty instead of the caller's user id.
- Quotes: `options.notifications: false` turns off the `quote.decided` owner notification; when sent, it carries the quote as its `subject_label`.
- Quotes and other line tables: a line table without a product type column keeps the product id when a version is restored, and `setLines` writes the id in the column's own type, such as `uuid`.
- Invoices: `recordPayment(invoiceId, { reason })` (SQL: a trailing `reason` on `record_invoice_payment`) is the history's reason for the status change a payment or refund causes.
- State machine: an app history table's `ip` column may be `text` or `inet`; a mapped `ip` no longer makes every transition fail.
