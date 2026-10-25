import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.push.options`. */
export type PushSqlOptions = { readonly extraColumns?: ExtraColumns };

export const pushSqlOptions: BlockOptionsSchema<PushSqlOptions> =
  blockOptions<PushSqlOptions>({ extraColumns: option.extraColumns() });
