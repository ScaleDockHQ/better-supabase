import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks["security-events"].options`. */
export type SecurityEventsSqlOptions = { readonly retention?: string };

export const securityEventsSqlOptions: BlockOptionsSchema<SecurityEventsSqlOptions> =
  blockOptions<SecurityEventsSqlOptions>({
    retention: option.string({ default: "7 days" }),
  });
