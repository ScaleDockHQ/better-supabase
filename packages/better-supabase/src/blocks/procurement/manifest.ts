import type { BlockOf } from "../define-block.ts";

import { bankingBlock } from "../banking/manifest.ts";
import { defineBlock } from "../define-block.ts";
import { inventoryBlock } from "../inventory/manifest.ts";
import { invoicesBlock } from "../invoices/manifest.ts";
import { rfqsBlock } from "../rfqs/manifest.ts";
import { createProcurement } from "./procurement.ts";

/** The blocks `procurement` is made of, by block name. */
export const procurementParts: {
  readonly rfqs: typeof rfqsBlock;
  readonly inventory: typeof inventoryBlock;
  readonly invoices: typeof invoicesBlock;
  readonly banking: typeof bankingBlock;
} = {
  rfqs: rfqsBlock,
  inventory: inventoryBlock,
  invoices: invoicesBlock,
  banking: bankingBlock,
};

export type ProcurementParts = typeof procurementParts;

/**
 * The `procurement` composite (ADR 0196): requests for quotation, stock,
 * supplier bills and bank payments, from sourcing to payment. It installs its
 * parts and sets their defaults; the parts stay ordinary blocks in the config.
 */
export const procurementBlock: BlockOf<
  "procurement",
  typeof createProcurement
> = defineBlock({
  name: "procurement",
  composes: procurementParts,
  create: createProcurement,
  category: "commerce",
});
