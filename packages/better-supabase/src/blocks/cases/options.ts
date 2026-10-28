import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.cases.options`. */
export interface CasesSqlOptions extends Readonly<Record<string, unknown>> {
  readonly extraColumns?: ExtraColumns;
  readonly severities?: readonly string[];
  readonly sources?: readonly string[];
  readonly kinds?: readonly string[];
}

export const casesSqlOptions: BlockOptionsSchema<CasesSqlOptions> =
  blockOptions<CasesSqlOptions>({
    extraColumns: option.extraColumns(),
    severities: option.strings(),
    sources: option.strings(),
    kinds: option.strings(),
  });
