---
"better-supabase": minor
---

A product import writes the product and a default variant. The price falls back from the selling price to the list price, then to the last purchase price times a markup. A name that is mostly control characters is refused, and a sku already used by another product is refused.
