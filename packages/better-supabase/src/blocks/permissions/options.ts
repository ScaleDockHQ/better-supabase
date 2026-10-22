import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.permissions.options`. */
export type PermissionsSqlOptions = {
  readonly platformRoleScope?: string;
  readonly scope?: string;
  readonly tenantRoleScope?: string;
};

export const permissionsSqlOptions: BlockOptionsSchema<PermissionsSqlOptions> =
  blockOptions<PermissionsSqlOptions>({
    platformRoleScope: option.string({ default: "platform" }),
    scope: option.string({ default: "organization" }),
    tenantRoleScope: option.string({ default: "tenant" }),
  });
