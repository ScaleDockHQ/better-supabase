import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.documents.options`. */
export type DocumentsSqlOptions = {
  readonly topic?: string;
  readonly maxUpdateBytes?: number;
  readonly compactAfter?: number;
};

export const documentsSqlOptions: BlockOptionsSchema<DocumentsSqlOptions> =
  blockOptions<DocumentsSqlOptions>({
    topic: option.string({ default: "documents" }),
    maxUpdateBytes: option.number({ default: 1_048_576 }),
    compactAfter: option.number({ default: 200 }),
  });
