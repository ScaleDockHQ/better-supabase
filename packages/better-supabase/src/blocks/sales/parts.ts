import type { PartClients } from "../define-block.ts";

import { contactsBlock } from "../contacts/manifest.ts";
import { dealsBlock } from "../deals/manifest.ts";
import { invoicesBlock } from "../invoices/manifest.ts";
import { ordersBlock } from "../orders/manifest.ts";
import { pipelinesBlock } from "../pipelines/manifest.ts";
import { quotesBlock } from "../quotes/manifest.ts";

/** The blocks `sales` is made of, by block name. */
export const salesParts: {
  readonly contacts: typeof contactsBlock;
  readonly pipelines: typeof pipelinesBlock;
  readonly deals: typeof dealsBlock;
  readonly quotes: typeof quotesBlock;
  readonly orders: typeof ordersBlock;
  readonly invoices: typeof invoicesBlock;
} = {
  contacts: contactsBlock,
  pipelines: pipelinesBlock,
  deals: dealsBlock,
  quotes: quotesBlock,
  orders: ordersBlock,
  invoices: invoicesBlock,
};

export type SalesParts = typeof salesParts;

/** The part clients `sales` receives. */
export type SalesClients = PartClients<SalesParts>;
