import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.qualifications.options`. */
export interface QualificationsSqlOptions extends Readonly<
  Record<string, unknown>
> {
  readonly extraColumns?: ExtraColumns;
  readonly holderTypes?: readonly string[];
  readonly renewalWindowDays?: number;
}

export const qualificationsSqlOptions: BlockOptionsSchema<QualificationsSqlOptions> =
  blockOptions<QualificationsSqlOptions>({
    extraColumns: option.extraColumns(),
    holderTypes: option.strings(),
    renewalWindowDays: option.number(),
  });
