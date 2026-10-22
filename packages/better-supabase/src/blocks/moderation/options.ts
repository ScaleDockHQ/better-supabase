import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.moderation.options`. */
export type ModerationSqlOptions = {
  /**
   * Open reports that hide visible content until a moderator decides; 0 turns
   * it off.
   */
  readonly autoHideThreshold?: number;
  /** The reasons a report may give, as lower-case keys. */
  readonly reasons?: readonly string[];
};

export const moderationSqlOptions: BlockOptionsSchema<ModerationSqlOptions> =
  blockOptions<ModerationSqlOptions>({
    autoHideThreshold: option.number({ default: 3 }),
    reasons: option.strings({
      default: ["spam", "abuse", "harassment", "off_topic", "illegal", "other"],
    }),
  });
