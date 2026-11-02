import type { BlockSqlContext } from "../context.ts";
import type { BlockSeeds, SeedTable } from "../seeds.ts";

import { sqlString } from "../../core/template.ts";
import { HOLIDAY_YEARS, HOLIDAYS, addDays } from "./calendar-holidays.ts";

const two = (value: number): string => String(value).padStart(2, "0");

/** A wall-clock midnight in the calendar's zone, as a SQL timestamptz. */
const midnight = (
  date: { year: number; month: number; day: number },
  tz: string,
): { sql: string } => ({
  sql: `timestamp '${date.year}-${two(date.month)}-${two(date.day)} 00:00' at time zone ${sqlString(tz)}`,
});

/**
 * `calendar.seeds`: one public holidays calendar per locale (`nl`, `de`, `fr`,
 * `en-gb` and `en-us`), with an all-day event per holiday for the years in
 * `HOLIDAY_YEARS`. Other locales, including `en`, seed none. Each event has a
 * stable `uid` such as `holiday-nl-2026-04-27`, so applying the defaults again
 * adds only new years. An app whose events table lacks a column the rows need
 * gets none.
 */
export const calendarSeeds: BlockSeeds = {
  defaults: (ctx: BlockSqlContext): readonly SeedTable[] => {
    if (
      !ctx.hasTable("calendars") ||
      !ctx.hasTable("events") ||
      !ctx.has("events", "uid")
    ) {
      return [];
    }

    const k = (column: string): string => ctx.col("calendars", column);
    const e = (column: string): string => ctx.col("events", column);

    return Object.entries(HOLIDAYS).flatMap(([locale, set]) => [
      {
        table: ctx.table("calendars"),
        tenantColumn: k("tenant"),
        key: [k("name")],
        locales: [locale],
        rows: [{ values: { [k("name")]: set.name, [k("tz")]: set.tz } }],
      },
      {
        table: ctx.table("events"),
        tenantColumn: e("tenant"),
        key: [e("uid")],
        locales: [locale],
        rows: HOLIDAY_YEARS.flatMap((year) =>
          set.rules.map((rule) => {
            const on = rule.on(year);

            return {
              values: {
                [e("uid")]:
                  `holiday-${locale}-${year}-${two(on.month)}-${two(on.day)}`,
                [e("calendar")]: {
                  ref: {
                    table: ctx.table("calendars"),
                    tenantColumn: k("tenant"),
                    match: { [k("name")]: set.name },
                    column: k("id"),
                  },
                },
                [e("title")]: rule.name,
                [e("startsAt")]: midnight(on, set.tz),
                [e("endsAt")]: midnight(addDays(on, 1), set.tz),
                [e("allDay")]: true,
                [e("tz")]: set.tz,
              },
            };
          }),
        ),
      },
    ]);
  },
};
