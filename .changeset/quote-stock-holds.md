---
"better-supabase": minor
---

Quotes take `options.holds`, which needs the inventory block. Sending a quote allocates stock for each tracked catalog line of the published version through `allocate_stock` (document type `quote_version`), keeping what isn't in stock on backorder. The holds end when the quote is revised to draft, withdrawn, expires or is rejected, and when `order_from_quote` makes its order, which allocates its own lines. Sending the next revision releases the earlier versions' holds. `release_quote_holds(quoteId)` releases them for the service role.
