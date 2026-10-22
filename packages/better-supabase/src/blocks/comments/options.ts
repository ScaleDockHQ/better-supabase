import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/**
 * `blocks.comments.options`. The body limit, documents and extra columns are
 * the messaging block's options, and the records come from `config.subjects`.
 */
export type CommentsSqlOptions = {
  readonly follow?: boolean;
  readonly mentionGroups?: unknown;
  /** `false` sends no `comment.posted` notification to the record's followers. */
  readonly notify?: boolean;
};

export const commentsSqlOptions: BlockOptionsSchema<CommentsSqlOptions> =
  blockOptions<CommentsSqlOptions>({
    follow: option.boolean({ default: true }),
    mentionGroups: option.unknown(),
    notify: option.boolean({ default: true }),
  });
