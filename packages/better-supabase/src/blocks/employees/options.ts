import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.employees.options`. */
export type EmployeesSqlOptions = {
  readonly employmentTypes?: readonly string[];
  readonly extraColumns?: unknown;
};

export const employeesSqlOptions: BlockOptionsSchema<EmployeesSqlOptions> =
  blockOptions<EmployeesSqlOptions>({
    employmentTypes: option.strings(),
    extraColumns: option.unknown(),
  });
