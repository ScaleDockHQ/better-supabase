import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.tags.options`. */
export type TagsSqlOptions = {
  readonly extraColumns?: ExtraColumns;
  /**
   * `create_tag` takes the caller's `slug`, and `update_tag` a `patch` that
   * sets `name`, `slug`, `color`, `description` and `kind` and can clear the
   * nullable ones.
   */
  readonly patch?: boolean;
};

export const tagsSqlOptions: BlockOptionsSchema<TagsSqlOptions> =
  blockOptions<TagsSqlOptions>({
    extraColumns: option.extraColumns(),
    patch: option.boolean({ default: false }),
  });
