import type { BlockOf } from "../define-block.ts";
import type { CatalogEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createCatalog } from "./catalog.ts";
import { catalogEvents } from "./events.ts";
import { catalogSqlOptions } from "./options.ts";
import { productInputSchema } from "./schemas.ts";

/** The `catalog` block's manifest (ADR 0029). */
export const catalogBlock: BlockOf<
  "catalog",
  typeof createCatalog,
  CatalogEvents
> = defineBlock({
  name: "catalog",
  sql: ["catalog"],
  options: { catalog: catalogSqlOptions },
  events: catalogEvents,
  create: createCatalog,
  category: "commerce",
  entities: {
    product: {
      mutability: "editable",
      emits: { create: true, update: true, delete: true },
    },
    product_variant: {
      mutability: "editable",
      emits: { create: true, update: true, delete: true },
    },
  },
  description:
    "Products with options, variants and prices in minor units, price lists, a category tree, collections, sales channels, translations per locale, product media and an optional public storefront.",
  recipes: ["product-catalog-grid"],
  schemas: { product: { input: productInputSchema } },
});
