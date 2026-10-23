import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.signatures.options`. */
export type SignaturesSqlOptions = { readonly extraColumns?: unknown };

export const signaturesSqlOptions: BlockOptionsSchema<SignaturesSqlOptions> =
  blockOptions<SignaturesSqlOptions>({ extraColumns: option.unknown() });
