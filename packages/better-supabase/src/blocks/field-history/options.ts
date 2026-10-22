import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.field-history.options`. */
export type FieldHistorySqlOptions = {
  /** Record type to the columns whose changes are kept: `{ deal: ["amount"] }`. */
  readonly subjects?: unknown;
};

export const fieldHistorySqlOptions: BlockOptionsSchema<FieldHistorySqlOptions> =
  blockOptions<FieldHistorySqlOptions>({ subjects: option.unknown() });
