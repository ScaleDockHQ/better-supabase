import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.waitlist.options`. */
export type WaitlistSqlOptions = {
  readonly defaultRole?: string;
  readonly codeField?: string;
  readonly roles?: readonly string[];
  readonly extraColumns?: unknown;
};

export const waitlistSqlOptions: BlockOptionsSchema<WaitlistSqlOptions> =
  blockOptions<WaitlistSqlOptions>({
    defaultRole: option.string({ default: "member" }),
    codeField: option.string({ default: "invite_code", client: true }),
    roles: option.strings(),
    extraColumns: option.unknown(),
  });
