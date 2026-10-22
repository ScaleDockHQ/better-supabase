import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.compliance.options`. */
export type ComplianceSqlOptions = { readonly extraColumns?: unknown };

export const complianceSqlOptions: BlockOptionsSchema<ComplianceSqlOptions> =
  blockOptions<ComplianceSqlOptions>({ extraColumns: option.unknown() });
