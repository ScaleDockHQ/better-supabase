---
"better-supabase": minor
---

Adopter gaps, round 40: column defaults and unique errors in the catalog, integer rank helpers, team feeds by an employees column, dated leave adjustments, withdrawing approved expenses, and per-year invoice numbering.

- Catalog: a new product, variant or category takes the column default for a value the call leaves out, instead of an explicit `null`, so `set_product_options` and `createVariant` work over a `title text not null default ''` column.
- Catalog: `CATALOG_SLUG_TAKEN` and `CATALOG_SKU_TAKEN` are raised only for an index on the slug or SKU column. Any other unique violation, such as an app index on a barcode, is raised unchanged with its constraint name.
- Catalog: with `options.rankType: "integer"` (now passed to the client through `blockConfig`), `reorderVariant`, `moveCategory` and `addToCollection` take `{ position }` or whole-number neighbors.
- Leave: `options.feed.teamColumn` shares a team feed by an employees column instead of team members, `feed.teamName` and `feed.organizationName` add the names, and `feed.confidential: "busy"` lists hidden confidential leave under `busy` without the type.
- Leave: `adjust` and `accrue` take `effectiveOn`.
- Expenses: `options.withdrawApproved` lets the owner, or `permissions.withdraw`, take an approved expense back to draft, and `permissions.deleteSubmitted` lets its holders delete a submitted or approved expense.
- Invoices: `options.uniqueNumber` (`"number"`, `"identifier"` or `false`) chooses the unique number index, so numbering that restarts each year works, and `options.linePositionKey: false` leaves out the unique line position index on your own line table.

Configs that set none of the new options or keys behave as before.
