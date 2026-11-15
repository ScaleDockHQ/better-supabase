# 1049: Archive, restore and purge for product variants (lane Y2)

- Status: accepted
- Date: 2026-11-15
- Amends: 1041, 1048

## Context

A variant has an `archived` status only when the app maps
`columns.variants.status`. Option changes already archive a variant that
something still references.

## Decision

`archive_variant` and `restore_variant` wrap `set_variant_status`, which records
`product_variant.archived` or `product_variant.restored` on the transition.
Restore sets `active`. Without a mapped status column both refuse with
`CATALOG_VARIANT_STATUS_UNSUPPORTED`. `add_to_cart` and `set_cart_line` refuse an
archived variant, and the storefront variants policy hides it.
`delete_variant` becomes `purge_variant`, records `product_variant.purged` and
needs `permissions.purge`, falling back to `catalog.manage`.

## Consequences

Breaking: `deleteVariant`, `delete_variant` and `product_variant.deleted`. An
app without a variant status keeps hard delete as purge only.
