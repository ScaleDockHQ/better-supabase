import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.sessions.options`. */
export type SessionsSqlOptions = {
  readonly exclude?: readonly string[];
  readonly policies?: boolean;
};

export const sessionsSqlOptions: BlockOptionsSchema<SessionsSqlOptions> =
  blockOptions<SessionsSqlOptions>({
    exclude: option.strings({ default: [] }),
    policies: option.boolean({ default: false }),
  });
