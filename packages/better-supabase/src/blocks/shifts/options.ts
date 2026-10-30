import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.shifts.options`. */
export type ShiftsSqlOptions = {
  /**
   * Hours a member rests between two shifts; assigning a shift inside them is
   * refused. `0` turns the check off. Default 11.
   */
  readonly minRestHours?: number;
  /**
   * `block` refuses an assignment that lacks a required qualification; `warn`
   * makes it and returns a warning. Default `block`.
   */
  readonly qualificationCheck?: "block" | "warn";
  /**
   * The IANA time zone template times and the days of `generateShifts`,
   * `publish` and `roster` are in. Default `UTC`.
   */
  readonly timeZone?: string;
  /** Extra columns on the shifts table. */
  readonly extraColumns?: ExtraColumns;
};

export const shiftsSqlOptions: BlockOptionsSchema<ShiftsSqlOptions> =
  blockOptions<ShiftsSqlOptions>({
    minRestHours: option.number({ default: 11 }),
    qualificationCheck: option.string<"block" | "warn">({ default: "block" }),
    timeZone: option.string({ default: "UTC" }),
    extraColumns: option.extraColumns(),
  });
