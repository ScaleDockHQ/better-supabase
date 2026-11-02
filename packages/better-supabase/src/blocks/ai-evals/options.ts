import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.ai-evals.options`. */
export type AiEvalsSqlOptions = { readonly maxItems?: number };

export const aiEvalsSqlOptions: BlockOptionsSchema<AiEvalsSqlOptions> =
  blockOptions<AiEvalsSqlOptions>({ maxItems: option.number() });
