---
"better-supabase": minor
---

The `catalog` block now keeps product identifiers (EAN, supplier and manufacturer codes), relations between variants (alternative, superseded by, accessory), supplier items with a column mapping per supplier and keyword search, and `promoteSupplierItem`, which creates a product from a supplier item on first use. Variants gain `setVariantTradeCode` for the CN code, and `inventory` locations gain `setLocationAddress`. The catalog contributes `supplier_item` and `product_identifier` import targets, so price lists and code lists load by external key. Existing installations get the new tables and columns from `better-supabase upgrade`; the new tables follow the `catalog` module to version 5 and `inventory` to version 4.
