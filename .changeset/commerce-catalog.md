---
"better-supabase": minor
---

Add the `catalog` block and SQL module (`better-supabase/blocks/catalog`): products with a draft, active and archived status, options and variants with per-organization SKUs, prices in bigint minor units per currency and price list with validity windows, a category tree, manual and rule collections, and an opt-in public storefront. `catalogSubjects()` registers products and variants as subjects. Grant `catalog.read` and `catalog.manage` to the roles that use it.
