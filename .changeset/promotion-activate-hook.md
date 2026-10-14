---
"better-supabase": minor
---

The `promotions` module calls `before_promotion_activate(promotion uuid)` when you define it, after every write that leaves a promotion active: `set_promotion_active(id, true)` and each `save_promotion` of an active promotion. Raising refuses the change, which holds a promotion for approval. The commerce recipe uses it to hold discounts above 30 percent, and now also indexes products for search and saves order grid views.
