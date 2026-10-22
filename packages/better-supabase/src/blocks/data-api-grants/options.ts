import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks['data-api-grants'].options`. */
export type DataApiGrantsSqlOptions = { readonly fromPolicies?: unknown };

export const dataApiGrantsSqlOptions: BlockOptionsSchema<DataApiGrantsSqlOptions> =
  blockOptions<DataApiGrantsSqlOptions>({ fromPolicies: option.unknown() });
