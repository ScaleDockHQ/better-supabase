import type { BlockOf } from "../define-block.ts";

import { catalogBlock } from "../catalog/manifest.ts";
import { defineBlock } from "../define-block.ts";
import { inventoryBlock } from "../inventory/manifest.ts";
import { ordersBlock } from "../orders/manifest.ts";
import { promotionsBlock } from "../promotions/manifest.ts";
import { createCommerce } from "./commerce.ts";

/** The blocks `commerce` is made of, by block name. */
export const commerceParts: {
  readonly catalog: typeof catalogBlock;
  readonly inventory: typeof inventoryBlock;
  readonly orders: typeof ordersBlock;
  readonly promotions: typeof promotionsBlock;
} = {
  catalog: catalogBlock,
  inventory: inventoryBlock,
  orders: ordersBlock,
  promotions: promotionsBlock,
};

export type CommerceParts = typeof commerceParts;

/**
 * The `commerce` composite (ADR 0196): a catalog, stock, orders and promotions.
 * It installs its parts and sets their defaults; the parts stay ordinary blocks
 * in the config.
 */
export const commerceBlock: BlockOf<"commerce", typeof createCommerce> =
  defineBlock({
    name: "commerce",
    composes: commerceParts,
    create: createCommerce,
    category: "commerce",
  });
