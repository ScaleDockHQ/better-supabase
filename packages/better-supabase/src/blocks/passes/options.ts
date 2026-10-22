import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.passes.options`. */
export type PassesSqlOptions = {
  /** How long before a booking starts its ticket admits, as a Postgres interval. */
  readonly checkInOpens?: string;
  /** How long a drop-in counts against a resource's capacity. */
  readonly dropInLength?: string;
};

export const passesSqlOptions: BlockOptionsSchema<PassesSqlOptions> =
  blockOptions<PassesSqlOptions>({
    checkInOpens: option.string({ default: "1 hour" }),
    dropInLength: option.string({ default: "2 hours" }),
  });
