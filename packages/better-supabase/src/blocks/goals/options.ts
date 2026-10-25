import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.goals.options`. */
export type GoalsSqlOptions = { readonly extraColumns?: ExtraColumns };

export const goalsSqlOptions: BlockOptionsSchema<GoalsSqlOptions> =
  blockOptions<GoalsSqlOptions>({ extraColumns: option.extraColumns() });
