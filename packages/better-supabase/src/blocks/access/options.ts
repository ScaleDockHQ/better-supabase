import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.access.options`. */
export type AccessSqlOptions = {
  readonly platformRoleScope?: string;
  readonly scope?: string;
  readonly tenantRoleScope?: string;
};

export const accessSqlOptions: BlockOptionsSchema<AccessSqlOptions> =
  blockOptions<AccessSqlOptions>({
    platformRoleScope: option.string({ default: "platform" }),
    scope: option.string({ default: "organization" }),
    tenantRoleScope: option.string({ default: "tenant" }),
  });
