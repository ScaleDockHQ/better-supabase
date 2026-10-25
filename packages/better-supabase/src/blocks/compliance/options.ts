import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.compliance.options`. */
export type ComplianceSqlOptions = { readonly extraColumns?: ExtraColumns };

export const complianceSqlOptions: BlockOptionsSchema<ComplianceSqlOptions> =
  blockOptions<ComplianceSqlOptions>({ extraColumns: option.extraColumns() });
