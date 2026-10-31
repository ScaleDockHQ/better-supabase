import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.lims.options`. */
export type LimsSqlOptions = {
  /**
   * The key of a qualification type (the qualifications block) that every
   * instrument must hold on the test date, such as `calibration`. A result then
   * needs an `instrumentId` that is an asset (the assets block) holding it.
   * Without it, instruments are optional and unchecked.
   */
  readonly instrumentQualification?: string;
  /**
   * The case kind (the cases block) an out of specification result opens.
   * Default `nonconformity`.
   */
  readonly nonconformityKind?: string;
};

export const limsSqlOptions: BlockOptionsSchema<LimsSqlOptions> =
  blockOptions<LimsSqlOptions>({
    instrumentQualification: option.string(),
    nonconformityKind: option.string(),
  });
