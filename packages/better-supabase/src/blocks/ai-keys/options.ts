import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks["ai-keys"].options`. */
export type AiKeysSqlOptions = { readonly pollEvery?: number };

export const aiKeysSqlOptions: BlockOptionsSchema<AiKeysSqlOptions> =
  blockOptions<AiKeysSqlOptions>({ pollEvery: option.number({ default: 60 }) });
