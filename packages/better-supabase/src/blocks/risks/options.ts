import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.risks.options`. */
export interface RisksSqlOptions extends Readonly<Record<string, unknown>> {
  readonly categories?: readonly string[];
  readonly extraColumns?: ExtraColumns;
}

export const risksSqlOptions: BlockOptionsSchema<RisksSqlOptions> =
  blockOptions<RisksSqlOptions>({
    categories: option.strings(),
    extraColumns: option.extraColumns(),
  });
