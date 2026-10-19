---
"better-supabase": minor
---

New block `better-supabase/blocks/reviews` (`better-supabase add reviews`): ratings and reviews of catalog products and other subjects. Any signed-in user can review an active product on a public storefront, a product in a catalog they read, or a registered subject in an organization they belong to, once per subject; a new review replaces their earlier one. `verified` is true when the `orders` module shows a paid order for the product, and `blocks.reviews.options.requirePurchase` makes that a requirement. Reviews wait for a moderator under `moderation: "pre"` (the default) or publish at once under `"post"`. `createReviews().summary()` returns each product's count, average and histogram, which anonymous visitors can read for a public storefront. The `access` module adds `reviews.manage` (admins); re-run `better-supabase sql sync` to pick up the new default permissions.
