# 1048: Archive, restore and purge for products (lane Y2)

- Status: accepted
- Date: 2026-11-15
- Amends: 1041

## Context

ADR 1041 puts `product` in its first group. A product already has an
`archived` status through `set_product_status`, so a second column would say the
same thing twice. Its read paths are the storefront policy, `channel_products`,
the cart and order lines, and search.

## Decision

`archive_product` and `restore_product` wrap `set_product_status`. Archive sets
the `archived` label. Restore sets `active`, or `draft` when the app has a draft
status, and does nothing for a product that is not archived. The status change
records `product.archived` or `product.restored` next to
`product.status_changed`, so there is no new column. `channel_products` hides
archived products unless `archived` is set (`true` lists only archived ones).
The storefront policy already shows only active products. `delete_product`
becomes `purge_product`, records `product.purged` and needs `permissions.purge`,
falling back to `catalog.manage`. Search reads `deletedAt`, not status, and is
unchanged.

## Consequences

Breaking: `deleteProduct`, `delete_product`, `product.deleted` and
`permissions.delete`. The 0.66 to 0.67 guide has the old-to-new table.
`channel_products` gains an `archived` argument, so its old signature is
dropped.
