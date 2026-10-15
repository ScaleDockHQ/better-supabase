import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.orders.options`. */
export type OrdersSqlOptions = {
  readonly paymentWindowMinutes?: number;
};

export const ordersSqlOptions: BlockOptionsSchema<OrdersSqlOptions> =
  blockOptions<OrdersSqlOptions>({
    paymentWindowMinutes: option.number({ default: 30 }),
  });
