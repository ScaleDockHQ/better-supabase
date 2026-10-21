import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.parties.options`. */
export type PartiesSqlOptions = {
  readonly companyLifecycles?: unknown;
  readonly personLifecycles?: unknown;
  readonly extraColumns?: unknown;
};

export const partiesSqlOptions: BlockOptionsSchema<PartiesSqlOptions> =
  blockOptions<PartiesSqlOptions>({
    companyLifecycles: option.unknown(),
    personLifecycles: option.unknown(),
    extraColumns: option.unknown(),
  });
