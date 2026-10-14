---
"better-supabase": minor
---

Add the `promotions` SQL module and `better-supabase/blocks/promotions`. Promotions take a percentage or a fixed amount off, or ship for free, for the whole cart or for products, categories (with their children) or manual collections. They apply automatically or by code, with single codes or generated batches, a minimum subtotal, a start and end, usage and per-customer limits, stacking rules and a priority. `orders` prices them into `priceCart`, lists the applied promotions, reports a code that doesn't apply as a cart problem, and redeems them at checkout with a row lock; cancelling an order releases its redemptions. Applied promotions in `PricedCart` and `Order` now carry their `kind`, and cart problems carry the `promotionId` and `reason`.
