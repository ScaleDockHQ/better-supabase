import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.calendar.options`. */
export type CalendarSqlOptions = { readonly extraColumns?: ExtraColumns };

export const calendarSqlOptions: BlockOptionsSchema<CalendarSqlOptions> =
  blockOptions<CalendarSqlOptions>({ extraColumns: option.extraColumns() });
