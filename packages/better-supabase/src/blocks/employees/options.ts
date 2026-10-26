import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.employees.options`. */
export type EmployeesSqlOptions = {
  readonly employmentTypes?: readonly string[];
  readonly extraColumns?: ExtraColumns;
  /**
   * Columns of the app's own on the private details table, which
   * `savePrivateDetails` takes under `fields`.
   */
  readonly privateDetailsExtraColumns?: ExtraColumns;
  /** Columns of the app's own on the contracts table, set from `fields`. */
  readonly contractExtraColumns?: ExtraColumns;
  readonly name?: "single" | "split";
  readonly privateDetails?: "json" | "flat";
  readonly contracts?: "append" | "editable";
  /** Whether the app's salary column holds minor or major units. */
  readonly salaryUnits?: "minor" | "major";
  /**
   * With editable contracts, `allow` adds a contract without the overlap check
   * and leaves the previous one as it is.
   */
  readonly contractOverlap?: "end" | "allow";
};

export const employeesSqlOptions: BlockOptionsSchema<EmployeesSqlOptions> =
  blockOptions<EmployeesSqlOptions>({
    employmentTypes: option.strings(),
    extraColumns: option.extraColumns(),
    privateDetailsExtraColumns: option.extraColumns(),
    contractExtraColumns: option.extraColumns(),
    name: option.string<"single" | "split">({ default: "single" }),
    privateDetails: option.string<"json" | "flat">({ default: "json" }),
    contracts: option.string<"append" | "editable">({ default: "append" }),
    salaryUnits: option.string<"minor" | "major">({ default: "minor" }),
    contractOverlap: option.string<"end" | "allow">({ default: "end" }),
  });
