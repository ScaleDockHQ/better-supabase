import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.time-tracking.options`. */
export type TimeTrackingSqlOptions = {
  readonly policy?: unknown;
  readonly timeZone?: string;
  readonly extraColumns?: ExtraColumns;
};

export const timeTrackingSqlOptions: BlockOptionsSchema<TimeTrackingSqlOptions> =
  blockOptions<TimeTrackingSqlOptions>({
    policy: option.unknown(),
    timeZone: option.string({ default: "UTC", client: true }),
    extraColumns: option.extraColumns(),
  });
