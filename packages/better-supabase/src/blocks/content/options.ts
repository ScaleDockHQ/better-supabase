import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.content.options`. */
export type ContentSqlOptions = {
  /** The entry types, such as `page` and `post`. Default `["page", "post"]`. */
  readonly types?: readonly string[];
  /**
   * The locales entries are written in; the first is the default. Default
   * `["en"]`.
   */
  readonly locales?: readonly string[];
  /**
   * Publishing and scheduling by a writer open an approvals request, and the
   * entry goes live once it is approved. Needs the approvals block. Default
   * false.
   */
  readonly requireApproval?: boolean;
  /**
   * The approvals policy a publish request follows. Default: one approval by
   * another member with `content.publish`.
   */
  readonly publishPolicy?: unknown;
  /**
   * The pg_cron schedule that publishes scheduled entries. Default every five
   * minutes; empty turns it off.
   */
  readonly publishSchedule?: string;
};

export const contentSqlOptions: BlockOptionsSchema<ContentSqlOptions> =
  blockOptions<ContentSqlOptions>({
    types: option.strings({ default: ["page", "post"] }),
    locales: option.strings({ default: ["en"] }),
    requireApproval: option.boolean({ default: false }),
    publishPolicy: option.unknown(),
    publishSchedule: option.string({ default: "*/5 * * * *" }),
  });
