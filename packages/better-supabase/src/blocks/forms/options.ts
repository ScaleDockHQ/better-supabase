import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.forms.options`. */
export type FormsSqlOptions = {
  readonly handlers?: unknown;
  readonly publicLimit?: unknown;
  readonly extraColumns?: unknown;
};

export const formsSqlOptions: BlockOptionsSchema<FormsSqlOptions> =
  blockOptions<FormsSqlOptions>({
    handlers: option.unknown(),
    publicLimit: option.unknown(),
    extraColumns: option.unknown(),
  });
