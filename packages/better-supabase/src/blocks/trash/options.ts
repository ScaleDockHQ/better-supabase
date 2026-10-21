import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.trash.options`. */
export type TrashSqlOptions = {
  readonly subjects?: unknown;
  readonly retentionDays?: number;
  readonly extraColumns?: unknown;
};

export const trashSqlOptions: BlockOptionsSchema<TrashSqlOptions> =
  blockOptions<TrashSqlOptions>({
    subjects: option.unknown(),
    retentionDays: option.number({ default: 30 }),
    extraColumns: option.unknown(),
  });
