import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.trash.options`. */
export type TrashSqlOptions = {
  readonly subjects?: unknown;
  readonly retentionDays?: number;
  readonly extraColumns?: unknown;
  /**
   * The column that marks a trashed row on tables outside `subjects`;
   * `trashExtension` filters on it and sets it on delete.
   */
  readonly deletedAt?: string;
};

export const trashSqlOptions: BlockOptionsSchema<TrashSqlOptions> =
  blockOptions<TrashSqlOptions>({
    subjects: option.unknown(),
    retentionDays: option.number({ default: 30 }),
    extraColumns: option.unknown(),
    deletedAt: option.string({ default: "deleted_at" }),
  });
