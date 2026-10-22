import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks['session-revocation'].options`. */
export type SessionRevocationSqlOptions = {
  readonly exclude?: readonly string[];
  readonly policies?: boolean;
};

export const sessionRevocationSqlOptions: BlockOptionsSchema<SessionRevocationSqlOptions> =
  blockOptions<SessionRevocationSqlOptions>({
    exclude: option.strings({ default: [] }),
    policies: option.boolean({ default: false }),
  });
