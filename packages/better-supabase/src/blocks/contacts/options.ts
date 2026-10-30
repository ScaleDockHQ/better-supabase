import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.contacts.options`. */
export type ContactsSqlOptions = {
  readonly companyLifecycles?: unknown;
  readonly personLifecycles?: unknown;
  /**
   * The roles a company or person can have, lowercase. Default `customer`,
   * `supplier`, `funder`, `partner`.
   */
  readonly roles?: readonly string[];
  readonly extraColumns?: ExtraColumns;
};

export const contactsSqlOptions: BlockOptionsSchema<ContactsSqlOptions> =
  blockOptions<ContactsSqlOptions>({
    companyLifecycles: option.unknown(),
    personLifecycles: option.unknown(),
    roles: option.strings(),
    extraColumns: option.extraColumns(),
  });
