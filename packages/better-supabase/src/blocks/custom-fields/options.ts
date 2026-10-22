import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.custom-fields.options`. */
export type CustomFieldsSqlOptions = {
  readonly layout?: string;
  /**
   * Writes one `read` audit entry per `read_field_values` call that returns an
   * encrypted or sensitive value. Needs the audit block.
   */
  readonly auditReads?: boolean;
};

export const customFieldsSqlOptions: BlockOptionsSchema<CustomFieldsSqlOptions> =
  blockOptions<CustomFieldsSqlOptions>({
    layout: option.string({ default: "normalized" }),
    auditReads: option.boolean({ default: false }),
  });
