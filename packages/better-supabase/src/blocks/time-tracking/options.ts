import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.time-tracking.options`. */
export type TimeTrackingSqlOptions = {
  readonly subjects?: unknown;
  readonly policy?: unknown;
  readonly timeZone?: string;
};

export const timeTrackingSqlOptions: BlockOptionsSchema<TimeTrackingSqlOptions> =
  blockOptions<TimeTrackingSqlOptions>({
    subjects: option.unknown(),
    policy: option.unknown(),
    timeZone: option.string({ default: "UTC", client: true }),
  });
