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
   * `end` (the default) ends the previous contract the day before a new one
   * starts. With editable contracts, `allow` adds a contract without the
   * overlap check and leaves the previous one as it is. `deny` refuses a
   * contract whose dates overlap another one, when it is added or changed.
   */
  readonly contractOverlap?: "end" | "allow" | "deny";
  /**
   * `reports: "manager"` (the default) moves the reports of an offboarded or
   * deleted employee to that employee's manager. `"keep"` leaves them under the
   * offboarded employee, and without a manager when the employee is deleted.
   */
  readonly offboarding?: { readonly reports?: "keep" | "manager" };
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
    contractOverlap: option.string<"end" | "allow" | "deny">({
      default: "end",
    }),
    offboarding: option.unknown<{ readonly reports?: "keep" | "manager" }>(),
  });
