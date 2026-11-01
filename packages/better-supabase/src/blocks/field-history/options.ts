import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks['field-history'].options`. */
export type FieldHistorySqlOptions = {
  /**
   * Partitions `field_changes` by month on `changed_at` (ADR 0038). The key
   * includes the timestamp, so the id comes from a sequence. A table created
   * before the option stays as it is. Needs the `changedAt` column. Default
   * `false`.
   */
  readonly partitioned?: boolean;
};

export const fieldHistorySqlOptions: BlockOptionsSchema<FieldHistorySqlOptions> =
  blockOptions<FieldHistorySqlOptions>({
    partitioned: option.boolean({ default: false }),
  });
