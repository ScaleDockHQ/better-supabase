---
"better-supabase": minor
---

Fixes from an app built on better-supabase: quote lines with checks across columns, answer keys, invoices from quotes and platform approval policies.

- Line items: `setLines` on quotes, deals and invoices, and the quote restore on acceptance, write each line's own columns and its `lineExtraColumns` in one statement, so a check across both holds (such as `check (pricing_mode <> 'fixed' or quantity = 1)`). A key a line's `fields` leaves out takes the column's default on a new line and keeps the stored value on an existing one.
- Extra columns: an insert that writes `extraColumns` without a key falls back to the column's default at run time when the configured type names none, so an app column `not null default false` works with the type `"boolean"`.
- Quotes: `permissions.accept`, `permissions.reject` and `permissions.requestChanges` give each answer of `decide` its own key, each falling back to `decide`.
- Quotes: `decide` with an `actor` on a quote past its valid-until date returns the expired quote instead of `{ status: "expired" }`, which the client could not read.
- Invoices: `fromQuote` keeps a line's product when the quote's line table has only a product id column, takes each issued deposit off per tax rate of its lines, and leaves out a copied line value the invoice column can't take. `options.depositLine` (`description` with `{identifier}`, `fields`) and `options.quoteLineValues` configure them, and `fromQuote(id, { depositDescription })` translates the description per call.
- Line items: `setLines` and the quote restore on acceptance also work when the app's line table keeps `position` as `numeric`.
- Invoices: `fromQuote` deducts a deposit on the final invoice's tax basis when the two differ in `pricesIncludeTax`, and leaves out deposits that credit notes fully credited.
- Invoices: `fromQuote` makes a new final invoice when the previous one was fully credited or archived. The opt-in `columns.invoices.archivedAt` names the app's archive column; archived deposits are not deducted either.
- Approvals: `permissions.platform` is the platform key for reading and editing platform policies; an organization's managers and platform staff without it are refused.

SQL signature: `invoice_from_quote(uuid, integer, bigint)` becomes `invoice_from_quote(uuid, integer, bigint, text default null)`; the old overload is dropped. Callers with the old arguments are unaffected.
