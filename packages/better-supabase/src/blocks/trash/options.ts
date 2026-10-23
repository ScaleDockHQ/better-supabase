import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.trash.options`. */
export type TrashSqlOptions = {
  readonly retentionDays?: number;
  readonly extraColumns?: unknown;
  /**
   * The column that marks a trashed row on tables outside `on`;
   * `trashExtension` filters on it and sets it on delete.
   */
  readonly deletedAt?: string;
};

export const trashSqlOptions: BlockOptionsSchema<TrashSqlOptions> =
  blockOptions<TrashSqlOptions>({
    retentionDays: option.number({ default: 30 }),
    extraColumns: option.unknown(),
    deletedAt: option.string({ default: "deleted_at" }),
  });
