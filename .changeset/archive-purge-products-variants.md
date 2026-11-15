---
"better-supabase": minor
---

Breaking: products and variants can be archived and restored, and their hard
delete is `purge`, behind `permissions.purge` (ADRs 1048 and 1049). Archive and
restore use the existing status, with no new column. `channelProducts` hides
archived products unless `archived` is set, and an archived variant can't be
added to a cart.

| Before                              | After                              |
| ----------------------------------- | ---------------------------------- |
| `catalog.deleteProduct(id)`         | `catalog.purgeProduct(id)`         |
| `delete_product(id)` (SQL)          | `purge_product(id)`                |
| `catalog.deleteVariant(id)`         | `catalog.purgeVariant(id)`         |
| `delete_variant(id)` (SQL)          | `purge_variant(id)`                |
| event `product.deleted`             | event `product.purged`             |
| event `product_variant.deleted`     | event `product_variant.purged`     |
| `blocks.catalog.permissions.delete` | `blocks.catalog.permissions.purge` |

Run `better-supabase upgrade` and apply the migration. See the 0.66 to 0.67
guide.
