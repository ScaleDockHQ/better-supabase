import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.segments.options`. */
export type SegmentsSqlOptions = {
  /** At most this many records in one segment. Default: 10000. */
  readonly maxMembers?: number;
};

export const segmentsSqlOptions: BlockOptionsSchema<SegmentsSqlOptions> =
  blockOptions<SegmentsSqlOptions>({ maxMembers: option.number() });
