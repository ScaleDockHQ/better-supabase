---
"better-supabase": minor
---

Quotes publish versions and price like European offers: VAT-inclusive prices, document discounts, deposits, sections and optional lines, and tax per rate (ADR 0120).

- Each `send` publishes the quote to `quote_versions`, a snapshot that never changes. `versions(quoteId)` lists them and `version(quoteId, revision)` returns the quote as it was sent.
- `pricesIncludeTax`, `discountBps`, `discountAmount` and `depositBps` on `create` and `update`. The database spreads the document discount over the tax rates and writes `quote.taxLines` (net, tax, gross and discount per rate), which add up exactly to the totals. `quote.pricing.depositDue` is the deposit asked.
- Lines take a `section` and can be `optional`. The customer picks optional lines when they accept (`selected` on `respond`, `decide` and `portalRespond`).
- `portalView` and `portalRespond` let a signed-in guest read and answer a quote shared with them, with no token. Answers record the user id, IP address and user agent (`decidedUserId`, `decidedIp`, `decidedUserAgent`).
- Invoices take `pricesIncludeTax`, and `fromQuote` invoices the lines the customer accepted with one `Discount` line per tax rate, so the invoice totals match the quote.

Breaking changes:

- `revise` keeps the same quote at the next revision instead of creating a new one, and refuses an accepted quote (`QUOTE_ACCEPTED`). `Quote.supersedesId`, the `supersedes_id` column and `QUOTE_ALREADY_REVISED` are removed; the migration drops the column.
- The `quote.revised` event carries `revision` instead of `revisionId`; `quote.sent` and `quote.accepted` carry `revision` too.
- `PublicQuote` returns `totals`, `pricing` and `taxLines` instead of top-level `subtotal`, `discountTotal`, `taxTotal` and `total`. `respond` resolves to `{ status, identifier, revision }`.
- `decide_quote` and `respond_to_quote` take a trailing `selected jsonb` argument; SQL callers that named the old signatures must use the new ones.
