import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.orders.options`. */
export type OrdersSqlOptions = {
  /**
   * The default title of a checkout invoice, with `{number}` for its number,
   * such as `Offerte {number}`. A title in the import item or the call still
   * wins. Default `Order {number}`.
   */
  readonly titleTemplate?: string;
  readonly paymentWindowMinutes?: number;
  /** Per-line preparation states and kitchen stations. Off by default. */
  readonly kitchen?: boolean;
  /**
   * Catalog variant lines without a `discountBps` or `unitAmount` take the
   * discount matrix's rule for the customer and quantity: its discount and its
   * fixed price (catalog `resolve_line_discount`). Needs the catalog block.
   * Default `false`, so lines price as before.
   */
  readonly discountMatrix?: boolean;
  /** Template rows take no number, no stock allocation and no order.placed. ADR 0244. */
  readonly templates?: boolean;
};

export const ordersSqlOptions: BlockOptionsSchema<OrdersSqlOptions> =
  blockOptions<OrdersSqlOptions>({
    titleTemplate: option.string({ default: "Order {number}" }),
    paymentWindowMinutes: option.number({ default: 30 }),
    kitchen: option.boolean({ default: false }),
    discountMatrix: option.boolean({ default: false }),
    templates: option.boolean({ default: false }),
  });
