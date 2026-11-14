import type { Result } from "../../core/result.ts";
import type { CalendarInfo } from "./calendar.ts";
import type { CalendarOccurrence, OccurrenceRange } from "./occurrences.ts";

import { ok } from "../../core/result.ts";
import { isRecord, oneOf, optionalText, recordsOf, textOf } from "../shared.ts";

/** What `Calendar.bootstrap` returns. */
export interface CalendarBootstrap {
  readonly calendars: CalendarInfo[];
  readonly occurrences: CalendarOccurrence[];
  readonly upcoming: CalendarOccurrence[];
  /** The caller's reminders; `eventId` is the series or event they sit on. */
  readonly reminders: {
    readonly id: string;
    readonly eventId: string;
    readonly offsetMinutes: number;
  }[];
}

/** A `list_calendars` row as a calendar. */
export function calendarInfoOf(row: Record<string, unknown>): CalendarInfo {
  const extra: Record<string, string> = {};

  for (const key of ["color", "ownerType", "ownerId", "description", "rank"]) {
    const found = optionalText(row[key]);

    if (found !== undefined) {
      extra[key] = found;
    }
  }

  return {
    id: textOf(row["id"]),
    name: textOf(row["name"]),
    tz: optionalText(row["tz"]) ?? "UTC",
    ...extra,
    ...(row["visibility"] === undefined
      ? {}
      : {
          visibility: oneOf(
            row["visibility"],
            ["shared", "private"] as const,
            "shared",
          ),
        }),
    ...(typeof row["isDefault"] === "boolean"
      ? { isDefault: row["isDefault"] }
      : {}),
    ...(isRecord(row["fields"]) ? { fields: { ...row["fields"] } } : {}),
  };
}

/**
 * A `calendar_bootstrap` row as calendars, occurrences and reminders. `expand`
 * turns the events under a key (`monthEvents`, `upcomingEvents`) into the
 * occurrences of a window.
 */
export async function bootstrapOf(
  row: Record<string, unknown>,
  expand: (
    key: string,
    window: OccurrenceRange,
  ) => Promise<Result<CalendarOccurrence[]>>,
  ranges: {
    readonly range: OccurrenceRange;
    readonly upcoming: OccurrenceRange | undefined;
  },
): Promise<Result<CalendarBootstrap>> {
  const month = await expand("monthEvents", ranges.range);

  if (!month.ok) {
    return month;
  }

  const next =
    ranges.upcoming === undefined
      ? ok<CalendarOccurrence[]>([])
      : await expand("upcomingEvents", ranges.upcoming);

  if (!next.ok) {
    return next;
  }

  return ok({
    calendars: recordsOf(row["calendarList"], "calendars").map(calendarInfoOf),
    occurrences: month.data,
    upcoming: next.data,
    reminders: recordsOf(row["myReminders"], "reminders").map((item) => ({
      id: textOf(item["id"]),
      eventId: textOf(item["subjectId"]),
      offsetMinutes: Number(item["offsetMinutes"]),
    })),
  });
}
