import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.care-plans.options`. */
export type CarePlansSqlOptions = {
  /**
   * The code systems a problem's code comes from, such as `snomed`, `icd-10` or
   * `omaha`. The first is the default. Default `custom`.
   */
  readonly codeSystems?: readonly string[];
  /**
   * The kinds of restrictive measure an action of kind `measure` takes, such as
   * `seclusion` or `supervision`. Default none: any text.
   */
  readonly measureKinds?: readonly string[];
  /**
   * Whether a guest with read access to the client (the guests block, such as a
   * representative) reads the client's published plans. Default `false`.
   */
  readonly guestRead?: boolean;
  /** Extra columns on the plans table, set through `fields`. */
  readonly extraColumns?: ExtraColumns;
};

export const carePlansSqlOptions: BlockOptionsSchema<CarePlansSqlOptions> =
  blockOptions<CarePlansSqlOptions>({
    codeSystems: option.strings(),
    measureKinds: option.strings(),
    guestRead: option.boolean(),
    extraColumns: option.extraColumns(),
  });
