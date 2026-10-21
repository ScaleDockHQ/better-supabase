import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.shared-signals.options`. */
export type SharedSignalsSqlOptions = { readonly retention?: string };

export const sharedSignalsSqlOptions: BlockOptionsSchema<SharedSignalsSqlOptions> =
  blockOptions<SharedSignalsSqlOptions>({
    retention: option.string({ default: "7 days" }),
  });
