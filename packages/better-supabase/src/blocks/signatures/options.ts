import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.signatures.options`. */
export type SignaturesSqlOptions = {
  /**
   * What a signature can mean, as lowercase names. A request's `meaning` must
   * be one of them. Default: `authored`, `reviewed`, `approved`, `released`,
   * `acknowledged` and `agreed`.
   */
  readonly meanings?: readonly string[];
};

export const signaturesSqlOptions: BlockOptionsSchema<SignaturesSqlOptions> =
  blockOptions<SignaturesSqlOptions>({ meanings: option.strings() });
