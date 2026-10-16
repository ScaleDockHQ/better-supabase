import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.comments.options`. */
export type CommentsSqlOptions = {
  readonly subjects?: unknown;
  readonly maxBodyLength?: number;
  readonly documentSchema?: unknown;
  readonly notify?: boolean;
  readonly follow?: boolean;
  readonly mentionGroups?: unknown;
  readonly extraColumns?: unknown;
};

export const commentsSqlOptions: BlockOptionsSchema<CommentsSqlOptions> =
  blockOptions<CommentsSqlOptions>({
    subjects: option.unknown(),
    maxBodyLength: option.number({ default: 10_000 }),
    documentSchema: option.unknown(),
    notify: option.boolean({ default: true }),
    follow: option.boolean({ default: true }),
    mentionGroups: option.unknown(),
    extraColumns: option.unknown(),
  });
