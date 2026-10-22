import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.goals.options`. */
export type GoalsSqlOptions = { readonly extraColumns?: unknown };

export const goalsSqlOptions: BlockOptionsSchema<GoalsSqlOptions> =
  blockOptions<GoalsSqlOptions>({ extraColumns: option.unknown() });
