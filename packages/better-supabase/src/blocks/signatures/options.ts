import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.signatures.options`. */
export type SignaturesSqlOptions = { readonly extraColumns?: ExtraColumns };

export const signaturesSqlOptions: BlockOptionsSchema<SignaturesSqlOptions> =
  blockOptions<SignaturesSqlOptions>({ extraColumns: option.extraColumns() });
