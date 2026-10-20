import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.billing.options`. */
export type BillingSqlOptions = {
  readonly seatRoles?: readonly string[];
  readonly plans?: unknown;
  readonly tenantKey?: unknown;
  /** Where subscriptions are read from. Default `sync-engine`. */
  readonly subscriptions?: string;
};

export const billingSqlOptions: BlockOptionsSchema<BillingSqlOptions> =
  blockOptions<BillingSqlOptions>({
    seatRoles: option.strings({ default: [] }),
    plans: option.unknown(),
    tenantKey: option.unknown(),
    subscriptions: option.string({ default: "sync-engine" }),
  });
