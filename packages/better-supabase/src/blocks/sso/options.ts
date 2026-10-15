import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.sso.options`. */
export type SsoSqlOptions = {
  readonly txtPrefix?: string;
  readonly defaultRole?: string;
  readonly roleOrder?: readonly string[];
  readonly groupRoles?: unknown;
};

export const ssoSqlOptions: BlockOptionsSchema<SsoSqlOptions> =
  blockOptions<SsoSqlOptions>({
    txtPrefix: option.string({ default: "_better-supabase" }),
    defaultRole: option.string({ default: "member" }),
    roleOrder: option.strings(),
    groupRoles: option.unknown(),
  });
