import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.signatures.options`. */
export type SignaturesSqlOptions = {
  readonly extraColumns?: ExtraColumns;
  /**
   * What a signature can mean, as lowercase names. A request's `meaning` must
   * be one of them. Default: `authored`, `reviewed`, `approved`, `released` and
   * `acknowledged`.
   */
  readonly meanings?: readonly string[];
};

export const signaturesSqlOptions: BlockOptionsSchema<SignaturesSqlOptions> =
  blockOptions<SignaturesSqlOptions>({
    extraColumns: option.extraColumns(),
    meanings: option.strings(),
  });
