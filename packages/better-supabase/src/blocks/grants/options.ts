import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.grants.options`. */
export type GrantsSqlOptions = { readonly fromPolicies?: unknown };

export const grantsSqlOptions: BlockOptionsSchema<GrantsSqlOptions> =
  blockOptions<GrantsSqlOptions>({ fromPolicies: option.unknown() });
