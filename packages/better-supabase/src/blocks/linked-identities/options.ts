import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks['linked-identities'].options`. */
export type LinkedIdentitiesSqlOptions = {
  readonly codeMinutes?: number;
  readonly verifiedEmails?: boolean;
};

export const linkedIdentitiesSqlOptions: BlockOptionsSchema<LinkedIdentitiesSqlOptions> =
  blockOptions<LinkedIdentitiesSqlOptions>({
    codeMinutes: option.number({ default: 10 }),
    verifiedEmails: option.boolean({ default: true }),
  });
