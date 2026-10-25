import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.contacts.options`. */
export type ContactsSqlOptions = {
  readonly companyLifecycles?: unknown;
  readonly personLifecycles?: unknown;
  readonly extraColumns?: ExtraColumns;
};

export const contactsSqlOptions: BlockOptionsSchema<ContactsSqlOptions> =
  blockOptions<ContactsSqlOptions>({
    companyLifecycles: option.unknown(),
    personLifecycles: option.unknown(),
    extraColumns: option.extraColumns(),
  });
