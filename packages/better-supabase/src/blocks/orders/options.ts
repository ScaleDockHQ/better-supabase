import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.orders.options`. */
export type OrdersSqlOptions = {
  readonly paymentWindowMinutes?: number;
  readonly extraColumns?: ExtraColumns;
  /** Per-line preparation states and kitchen stations. Off by default. */
  readonly kitchen?: boolean;
};

export const ordersSqlOptions: BlockOptionsSchema<OrdersSqlOptions> =
  blockOptions<OrdersSqlOptions>({
    paymentWindowMinutes: option.number({ default: 30 }),
    extraColumns: option.extraColumns(),
    kitchen: option.boolean({ default: false }),
  });
