import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.streams.options`. */
export type StreamsSqlOptions = { readonly topic?: string };

export const streamsSqlOptions: BlockOptionsSchema<StreamsSqlOptions> =
  blockOptions<StreamsSqlOptions>({
    topic: option.string({ default: "stream" }),
  });
