import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks['sessions'].options`. */
export type SessionsSqlOptions = {
  /**
   * Wrapper name to `schema.function`; renders
   * `better_supabase.bootstrap_<name>`.
   */
  readonly bootstrap?: Readonly<Record<string, string>>;
  readonly exclude?: readonly string[];
  readonly policies?: boolean;
};

export const sessionsSqlOptions: BlockOptionsSchema<SessionsSqlOptions> =
  blockOptions<SessionsSqlOptions>({
    bootstrap: option.unknown<Readonly<Record<string, string>>>(),
    exclude: option.strings({ default: [] }),
    policies: option.boolean({ default: false }),
  });
