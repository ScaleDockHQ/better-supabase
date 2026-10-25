import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.invoices.options`. */
export type InvoicesSqlOptions = {
  readonly company?: string;
  readonly contact?: string;
  readonly prefix?: string;
  readonly creditPrefix?: string;
  readonly termsDays?: number;
  readonly extraColumns?: ExtraColumns;
};

export const invoicesSqlOptions: BlockOptionsSchema<InvoicesSqlOptions> =
  blockOptions<InvoicesSqlOptions>({
    company: option.string({ default: "company" }),
    contact: option.string({ default: "person" }),
    prefix: option.string({ default: "INV-" }),
    creditPrefix: option.string({ default: "CN-" }),
    termsDays: option.number({ default: 30 }),
    extraColumns: option.extraColumns(),
  });
