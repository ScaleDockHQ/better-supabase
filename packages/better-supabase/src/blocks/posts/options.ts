import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.posts.options`. */
export type PostsSqlOptions = {
  /**
   * "post" shows a new post at once and moderates it after a report; "pre"
   * holds new posts, and authors' edits, for a moderator. Default "post".
   */
  readonly moderation?: string;
  /** The longest post body, in characters. Default 20000. */
  readonly maxBodyLength?: number;
  readonly extraColumns?: unknown;
};

export const postsSqlOptions: BlockOptionsSchema<PostsSqlOptions> =
  blockOptions<PostsSqlOptions>({
    moderation: option.string({ default: "post" }),
    maxBodyLength: option.number({ default: 20_000 }),
    extraColumns: option.unknown(),
  });
