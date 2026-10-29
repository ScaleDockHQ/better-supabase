import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.inspections.options`. */
export interface InspectionsSqlOptions extends Readonly<Record<string, unknown>> {
  readonly extraColumns?: ExtraColumns;
  readonly kinds?: readonly string[];
  readonly findingTypes?: readonly string[];
  readonly caseFindingTypes?: readonly string[];
}

export const inspectionsSqlOptions: BlockOptionsSchema<InspectionsSqlOptions> =
  blockOptions<InspectionsSqlOptions>({
    extraColumns: option.extraColumns(),
    kinds: option.strings(),
    findingTypes: option.strings(),
    caseFindingTypes: option.strings(),
  });
