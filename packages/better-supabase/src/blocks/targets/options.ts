import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.targets.options`. */
export type TargetsSqlOptions = { readonly extraColumns?: unknown };

export const targetsSqlOptions: BlockOptionsSchema<TargetsSqlOptions> =
  blockOptions<TargetsSqlOptions>({ extraColumns: option.unknown() });
