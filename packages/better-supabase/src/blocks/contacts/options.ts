import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.contacts.options`. */
export type ContactsSqlOptions = {
  readonly companyLifecycles?: unknown;
  readonly personLifecycles?: unknown;
  readonly extraColumns?: unknown;
};

export const contactsSqlOptions: BlockOptionsSchema<ContactsSqlOptions> =
  blockOptions<ContactsSqlOptions>({
    companyLifecycles: option.unknown(),
    personLifecycles: option.unknown(),
    extraColumns: option.unknown(),
  });
