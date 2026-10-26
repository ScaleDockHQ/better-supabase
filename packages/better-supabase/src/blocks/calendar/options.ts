import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

export type CalendarAccessFunctions = {
  readonly read?: string;
  readonly write?: string;
};

/** `blocks.calendar.options`. */
export type CalendarSqlOptions = {
  readonly extraColumns?: ExtraColumns;
  /**
   * Columns of the app's own on the calendars table, which `create_calendar`
   * takes as `fields` and `list_calendars` returns under `fields`.
   */
  readonly calendarExtraColumns?: ExtraColumns;
  readonly access?: boolean;
  readonly accessFunctions?: CalendarAccessFunctions;
  readonly userFeed?: boolean;
  readonly recurrence?: "inline" | "table";
  readonly rdates?: boolean;
  readonly attendeeKey?: "email" | "any";
  readonly calendarDetails?: boolean;
};

export const calendarSqlOptions: BlockOptionsSchema<CalendarSqlOptions> =
  blockOptions<CalendarSqlOptions>({
    extraColumns: option.extraColumns(),
    calendarExtraColumns: option.extraColumns(),
    access: option.boolean({ default: false }),
    accessFunctions: option.unknown<CalendarAccessFunctions>(),
    userFeed: option.boolean({ default: false }),
    recurrence: option.string<"inline" | "table">({ default: "inline" }),
    rdates: option.boolean({ default: false }),
    attendeeKey: option.string<"email" | "any">({ default: "email" }),
    calendarDetails: option.boolean({ default: false }),
  });
