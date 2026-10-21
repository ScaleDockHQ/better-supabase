import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.reactions.options`. */
export type ReactionsSqlOptions = {
  readonly subjects?: unknown;
  readonly topic?: string;
};

export const reactionsSqlOptions: BlockOptionsSchema<ReactionsSqlOptions> =
  blockOptions<ReactionsSqlOptions>({
    subjects: option.unknown(),
    topic: option.string({ default: "reactions", client: true }),
  });
