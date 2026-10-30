import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks['imports'].options`. */
export type ImportsSqlOptions = { readonly targets?: unknown };

export const importsSqlOptions: BlockOptionsSchema<ImportsSqlOptions> =
  blockOptions<ImportsSqlOptions>({ targets: option.unknown() });
