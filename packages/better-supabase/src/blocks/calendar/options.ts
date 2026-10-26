import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.calendar.options`. */
export type CalendarSqlOptions = {
  readonly extraColumns?: ExtraColumns;
  /**
   * Columns of the app's own on the calendars table, which `create_calendar`
   * takes as `fields` and `list_calendars` returns under `fields`.
   */
  readonly calendarExtraColumns?: ExtraColumns;
};

export const calendarSqlOptions: BlockOptionsSchema<CalendarSqlOptions> =
  blockOptions<CalendarSqlOptions>({
    extraColumns: option.extraColumns(),
    calendarExtraColumns: option.extraColumns(),
  });
