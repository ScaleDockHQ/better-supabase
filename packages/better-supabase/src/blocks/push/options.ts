import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.push.options`. */
export type PushSqlOptions = {
  readonly extraColumns?: unknown;
};

export const pushSqlOptions: BlockOptionsSchema<PushSqlOptions> =
  blockOptions<PushSqlOptions>({
    extraColumns: option.unknown(),
  });
