---
"better-supabase": minor
---

Add the `orders` block and SQL module (`better-supabase/blocks/orders`). Carts belong to the signed-in user, anonymous users included, and `mergeCarts` moves them to the account the shopper signs in to. `checkout` prices the cart from the catalog, quotes tax through a `TaxProvider`, places the order with a number from `number-sequences`, reserves inventory and creates the payment through a `PaymentProvider` with an idempotency key. Paid orders turn their reservations into sale movements and get an invoice number. Fulfillments, returns and refunds (with a proportional tax reversal) follow, and orders emit `order.*`, `fulfillment.*` and `return.*` subject events. Grant `orders.read` and `orders.manage` to the roles that run the shop.

`sqlTransport` now sends an array of objects as JSON, so `jsonb` arguments that take a list work over it.
