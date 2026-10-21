import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.ai-providers.options`. */
export type AiProvidersSqlOptions = { readonly pollEvery?: number };

export const aiProvidersSqlOptions: BlockOptionsSchema<AiProvidersSqlOptions> =
  blockOptions<AiProvidersSqlOptions>({
    pollEvery: option.number({ default: 60 }),
  });
