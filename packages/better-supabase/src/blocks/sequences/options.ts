import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.sequences.options`. */
export type SequencesSqlOptions = {
  /** Send attempts of an email step before the run exits as failed. Default 3. */
  readonly maxAttempts?: number;
  /**
   * Minutes before a failed email step runs again, times the attempts so far.
   * Default 15.
   */
  readonly retryMinutes?: number;
};

export const sequencesSqlOptions: BlockOptionsSchema<SequencesSqlOptions> =
  blockOptions<SequencesSqlOptions>({
    maxAttempts: option.number({ default: 3 }),
    retryMinutes: option.number({ default: 15 }),
  });
