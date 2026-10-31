import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.orders.options`. */
export type OrdersSqlOptions = {
  readonly paymentWindowMinutes?: number;
  readonly extraColumns?: ExtraColumns;
  /** Per-line preparation states and kitchen stations. Off by default. */
  readonly kitchen?: boolean;
  /**
   * Catalog variant lines without a `discountBps` or `unitAmount` take the
   * discount matrix's rule for the customer and quantity: its discount and its
   * fixed price (catalog `resolve_line_discount`). Needs the catalog block.
   * Default `false`, so lines price as before.
   */
  readonly discountMatrix?: boolean;
};

export const ordersSqlOptions: BlockOptionsSchema<OrdersSqlOptions> =
  blockOptions<OrdersSqlOptions>({
    paymentWindowMinutes: option.number({ default: 30 }),
    extraColumns: option.extraColumns(),
    kitchen: option.boolean({ default: false }),
    discountMatrix: option.boolean({ default: false }),
  });
