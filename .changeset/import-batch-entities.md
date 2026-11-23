---
"better-supabase": minor
---

The `party`, `product`, `stock_allocation` and `stock_count` import entities write the new rows of a batch in one statement per table through `import_party_batch`, `import_product_batch`, `import_stock_allocation_batch` and `import_stock_count_batch`. With 2,000 new items an import takes 39 to 55 percent less time; results, counts, errors and the record map match the one-row path, which still handles updates and every item with a conflict in its batch. `supplier_item` and `asset` keep the one-row path, which was already faster than the gain. Run `better-supabase upgrade` (ADR 1217).
