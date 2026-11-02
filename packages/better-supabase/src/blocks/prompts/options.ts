import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.prompts.options`. */
export type PromptsSqlOptions = { readonly maxBytes?: number };

export const promptsSqlOptions: BlockOptionsSchema<PromptsSqlOptions> =
  blockOptions<PromptsSqlOptions>({ maxBytes: option.number() });
