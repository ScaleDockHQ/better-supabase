import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.calendar.options`. */
export type CalendarSqlOptions = { readonly extraColumns?: unknown };

export const calendarSqlOptions: BlockOptionsSchema<CalendarSqlOptions> =
  blockOptions<CalendarSqlOptions>({ extraColumns: option.unknown() });
