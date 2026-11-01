import type { ShareLinkFeedOptions } from "../feed-options.ts";
import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/**
 * How structured rule columns store BYDAY and BYMONTHDAY: weekday codes in
 * lower case, one month day per rule, and an ordinal weekday (`2TU`) in two
 * columns of the app's rules table.
 */
export type CalendarRuleDialect = {
  readonly weekdays?: "upper" | "lower";
  readonly monthDay?: "list" | "scalar";
  readonly ordinal?: { readonly weekday: string; readonly position: string };
};

export type CalendarReadOnly = {
  readonly column: string;
  readonly values: readonly string[];
};

/**
 * An app function `schema.name(calendar_id uuid, user_id uuid)`, or the
 * authorization provider's per-row grants of `key` on its resource `rows` (its
 * `rowsWithFor` template, answered for the user asked about).
 */
export type CalendarAccessHook =
  | string
  | { readonly rows: string; readonly key: string };

export type CalendarAccessFunctions = {
  readonly read?: CalendarAccessHook;
  readonly write?: CalendarAccessHook;
  readonly share?: CalendarAccessHook;
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
  readonly feed?: ShareLinkFeedOptions;
  readonly recurrence?: "inline" | "table";
  readonly rdates?: boolean;
  readonly attendeeKey?: "email" | "any";
  readonly calendarDetails?: boolean;
  readonly ruleDialect?: CalendarRuleDialect;
  readonly readOnly?: CalendarReadOnly;
  /**
   * Alarms per calendar (`calendar_default_alarms`) that `save_calendar_event`
   * copies onto a new event that sets no `alarms`. Needs the alarms table.
   */
  readonly defaultAlarms?: boolean;
  /**
   * Adds a gist exclusion constraint (ADR 0198) so a calendar has no two
   * opaque, single, timed events at the same time. Needs `btree_gist`, which
   * the module creates. Rows that already overlap make the migration fail.
   * Default `false`.
   */
  readonly noOverlap?: boolean;
};

export const calendarSqlOptions: BlockOptionsSchema<CalendarSqlOptions> =
  blockOptions<CalendarSqlOptions>({
    extraColumns: option.extraColumns(),
    calendarExtraColumns: option.extraColumns(),
    access: option.boolean({ default: false }),
    accessFunctions: option.unknown<CalendarAccessFunctions>(),
    userFeed: option.boolean({ default: false }),
    feed: option.unknown<ShareLinkFeedOptions>(),
    recurrence: option.string<"inline" | "table">({ default: "inline" }),
    rdates: option.boolean({ default: false }),
    attendeeKey: option.string<"email" | "any">({ default: "email" }),
    calendarDetails: option.boolean({ default: false }),
    ruleDialect: option.unknown<CalendarRuleDialect>(),
    readOnly: option.unknown<CalendarReadOnly>(),
    defaultAlarms: option.boolean({ default: false }),
    noOverlap: option.boolean({ default: false }),
  });
