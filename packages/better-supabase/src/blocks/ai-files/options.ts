import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.ai-files.options`. */
export type AiFilesSqlOptions = {
  readonly bucket?: string;
  readonly maxSize?: number;
  readonly allowedMimeTypes?: readonly string[];
  readonly pendingTtl?: string;
};

export const aiFilesSqlOptions: BlockOptionsSchema<AiFilesSqlOptions> =
  blockOptions<AiFilesSqlOptions>({
    bucket: option.string({ default: "ai-files" }),
    maxSize: option.number(),
    allowedMimeTypes: option.strings({ default: [] }),
    pendingTtl: option.string({ default: "1 day" }),
  });
