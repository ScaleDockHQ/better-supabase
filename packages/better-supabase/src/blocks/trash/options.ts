import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.trash.options`. */
export type TrashSqlOptions = {
  readonly subjects?: unknown;
  readonly retentionDays?: number;
};

export const trashSqlOptions: BlockOptionsSchema<TrashSqlOptions> =
  blockOptions<TrashSqlOptions>({
    subjects: option.unknown(),
    retentionDays: option.number({ default: 30 }),
  });
