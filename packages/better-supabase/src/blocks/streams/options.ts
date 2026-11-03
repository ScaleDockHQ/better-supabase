import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.streams.options`. */
export type StreamsSqlOptions = {
  readonly topic?: string;
  /**
   * A pg_cron schedule that runs `purge_streams`, every quarter hour in cron
   * syntax. Empty (the default) schedules nothing.
   */
  readonly purgeSchedule?: string;
  /** How long a closed stream is kept: a Postgres interval. Default `1 day`. */
  readonly purgeOlderThan?: string;
};

export const streamsSqlOptions: BlockOptionsSchema<StreamsSqlOptions> =
  blockOptions<StreamsSqlOptions>({
    topic: option.string({ default: "stream" }),
    purgeSchedule: option.string({ default: "" }),
    purgeOlderThan: option.string({ default: "1 day" }),
  });
