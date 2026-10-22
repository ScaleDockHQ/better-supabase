import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.scores.options`. */
export type ScoresSqlOptions = {
  /** The most rules one score model may hold. */
  readonly maxRules?: number;
  /** The most metrics one score model may hold. */
  readonly maxMetrics?: number;
};

export const scoresSqlOptions: BlockOptionsSchema<ScoresSqlOptions> =
  blockOptions<ScoresSqlOptions>({
    maxRules: option.number({ default: 100 }),
    maxMetrics: option.number({ default: 50 }),
  });
