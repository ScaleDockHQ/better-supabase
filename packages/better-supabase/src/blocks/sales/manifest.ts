import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { salesParts } from "./parts.ts";
import { createSales } from "./sales.ts";

/**
 * The `sales` composite (ADR 0177): contacts, pipelines, deals, quotes, orders
 * and invoices, with the helpers that carry a deal to cash.
 */
export const salesBlock: BlockOf<"sales", typeof createSales> = defineBlock({
  name: "sales",
  composes: salesParts,
  create: createSales,
  category: "crm",
});
