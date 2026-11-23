---
"better-supabase": minor
---

Breaking: order, fulfillment and return line quantities are `numeric`, with
`options.quantityScale` (0 to 6, default 0) setting how many decimals a quantity may have. Staff
orders carry `channel`, `source` and `externalId` (unique per organization and source, and
idempotent like `origin`), `invoicingPolicy`, `deliveryMethod`, `quoteId`, `orderDiscount`,
`promotionId`, `paymentRequired` with a `deposit`, and a `party`. Lines take `unit`,
`description`, `lineType` and the extra columns your schema files add. `orderPage`, `orderFacets`
and `orderCount` page orders by keyset from `page_orders`. The orders block moves to version 5;
rename a column of your own that one of the new block columns takes (ADR 1224).
