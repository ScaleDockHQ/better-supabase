import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.ai-guardrails.options`. */
export type AiGuardrailsSqlOptions = { readonly retention?: string };

export const aiGuardrailsSqlOptions: BlockOptionsSchema<AiGuardrailsSqlOptions> =
  blockOptions<AiGuardrailsSqlOptions>({ retention: option.string() });
