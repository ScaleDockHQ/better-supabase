import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.saved-views.options`. */
export type SavedViewsSqlOptions = {
  readonly extraColumns?: unknown;
};

export const savedViewsSqlOptions: BlockOptionsSchema<SavedViewsSqlOptions> =
  blockOptions<SavedViewsSqlOptions>({
    extraColumns: option.unknown(),
  });
