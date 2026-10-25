import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.employees.options`. */
export type EmployeesSqlOptions = {
  readonly employmentTypes?: readonly string[];
  readonly extraColumns?: ExtraColumns;
};

export const employeesSqlOptions: BlockOptionsSchema<EmployeesSqlOptions> =
  blockOptions<EmployeesSqlOptions>({
    employmentTypes: option.strings(),
    extraColumns: option.extraColumns(),
  });
