import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks["service-accounts"].options`. */
export type ServiceAccountsSqlOptions = {
  readonly extraColumns?: ExtraColumns;
};

export const serviceAccountsSqlOptions: BlockOptionsSchema<ServiceAccountsSqlOptions> =
  blockOptions<ServiceAccountsSqlOptions>({
    extraColumns: option.extraColumns(),
  });
