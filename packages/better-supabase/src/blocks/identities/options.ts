import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.identities.options`. */
export type IdentitiesSqlOptions = {
  readonly codeMinutes?: number;
  readonly verifiedEmails?: boolean;
};

export const identitiesSqlOptions: BlockOptionsSchema<IdentitiesSqlOptions> =
  blockOptions<IdentitiesSqlOptions>({
    codeMinutes: option.number({ default: 10 }),
    verifiedEmails: option.boolean({ default: true }),
  });
