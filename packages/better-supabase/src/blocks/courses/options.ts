import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.courses.options`. */
export type CoursesSqlOptions = {
  /** Extra columns on the courses table: column name to SQL type. */
  readonly extraColumns?: ExtraColumns;
};

export const coursesSqlOptions: BlockOptionsSchema<CoursesSqlOptions> =
  blockOptions<CoursesSqlOptions>({ extraColumns: option.extraColumns() });
