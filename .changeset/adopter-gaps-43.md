---
"better-supabase": minor
---

Adopter gaps, round 43: quotes whose totals the app keeps, app columns on version lines, fixed deposits and header discounts on invoices from quotes, finer quote keys, sending a declined quote again in one call, and actors on every quote status change.

- Quotes: `options.totals: "app"` leaves the totals to the app (fixed line discounts, VAT regimes such as reverse charge): no recount, `depositDue` follows the app's total, and a trigger refuses a totals change once a quote is answered, expired or withdrawn (`QUOTE_TOTALS_FROZEN`).
- Quotes: `options.versionLineExtraColumns` adds columns to `quote_version_lines`, which each publish copies from the line columns of the same name.
- Quotes: `permissions.send`, `decide` and `withdraw` take their own keys, each falling back to `write`.
- Quotes: `options.resend` lets `send` and `publish` take a rejected, withdrawn or expired quote and send it as the next revision in one call. `withdraw` also takes an expired quote.
- Quotes: opening a quote by link or portal passes the viewer to the state machine's history, `portalView` takes an `actor` from the service role (SQL: `portal_quote(quote, actor)`), and `expire_quotes` clears the actor.
- Invoices: `fromQuote(quoteId, { depositAmount })` makes a fixed deposit invoice (SQL: `invoice_from_quote(quote, deposit_bps, deposit_amount)`), and both invoices copy the line and header extra columns the quote shares.
- Invoices: opt-in `depositAmount`, `discountBps` and `discountAmount` columns; with the discount columns the final invoice keeps the quote's document discount on its header. `options.depositKind` marks deposit invoices by a kind value and finds them by it and the quote link.
