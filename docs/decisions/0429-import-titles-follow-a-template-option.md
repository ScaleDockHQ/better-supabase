# 0429: Default import titles come from a template option

- Status: accepted
- Date: 2026-11-09
- Amends: 0141

## Context

The quote, invoice, opening-balance and checkout-invoice import functions wrote
English default titles (`Quote Q-1`, `Invoice INV-1`, `Opening balance 7`,
`Order 12`) in SQL. A tenant that works in another language got English titles in
its records and, for an opening balance, in the ledger line description.

## Decision

Each module reads a text option with `{number}` for the number:
`quotes.titleTemplate` (`Quote {number}`), `invoices.titleTemplate`
(`Invoice {number}`), `invoices.openingTitleTemplate` (`Opening balance {number}`)
and `orders.titleTemplate` (`Order {number}`). The SQL renders
`replace('<template>', '{number}', <number>)`, so the template is a constant in
the function and a title in the item or call still wins. Locale rules are data: the
library names no language. Localized seed rows (brief 6.2) are not in this change.

## Consequences

`better-supabase upgrade` rewrites the quotes, invoices and orders modules and the
next schema migration replaces their import and checkout functions. No data
migration; stored titles do not change. A unit test renders each default and a
custom template and escapes a quote.
