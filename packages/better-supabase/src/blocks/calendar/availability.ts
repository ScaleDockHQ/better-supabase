import type { OccurrenceRange } from "./occurrences.ts";

import { optionalText, recordsOf, requiredInstant, textOf } from "../shared.ts";

/**
 * What an event is: a meeting, a block the owner is away (`out_of_office`), or
 * time they keep for deep work (`focus_time`).
 */
export type CalendarEventKind = "event" | "out_of_office" | "focus_time";

/** `transparent` events don't make anyone busy (RFC 5545 `TRANSP`). */
export type CalendarTransparency = "opaque" | "transparent";

export const CALENDAR_EVENT_KINDS: readonly CalendarEventKind[] = [
  "event",
  "out_of_office",
  "focus_time",
];

export const CALENDAR_TRANSPARENCIES: readonly CalendarTransparency[] = [
  "opaque",
  "transparent",
];

/** One stretch of a weekday, in `HH:MM` local time (`end` may be `24:00`). */
export interface WeeklyHours {
  /** ISO weekday: 1 is Monday, 7 is Sunday. */
  readonly weekday: 1 | 2 | 3 | 4 | 5 | 6 | 7;
  readonly start: string;
  readonly end: string;
}

export interface WorkingHours {
  readonly userId: string;
  readonly tz: string;
  readonly hours: readonly WeeklyHours[];
}

export interface WorkingHoursInput {
  /** IANA time zone the hours are in. */
  readonly tz: string;
  /** An empty list clears them. */
  readonly hours: readonly WeeklyHours[];
  /** Default the signed-in user; calendar managers can set anyone's. */
  readonly userId?: string;
}

/** A half-open range of instants. */
export interface BusyRange {
  readonly from: Temporal.Instant;
  readonly until: Temporal.Instant;
}

/** When one member is busy, merged and clipped to the asked range. */
export interface FreeBusy {
  readonly userId: string;
  /** Every busy range: events, out of office, focus time and leave. */
  readonly busy: readonly BusyRange[];
  readonly outOfOffice: readonly BusyRange[];
  readonly focusTime: readonly BusyRange[];
  /** Their working hours in the range; absent when they set none. */
  readonly workingHours?: readonly BusyRange[];
  readonly tz?: string;
}

export interface CommonFreeTimeOptions {
  /** The shortest free range worth returning. Default zero. */
  readonly minimum?: Temporal.Duration;
  /**
   * Keep only the time inside everyone's working hours (members without working
   * hours don't narrow it). Default `true`.
   */
  readonly workingHours?: boolean;
}

const WEEKDAYS = new Set([1, 2, 3, 4, 5, 6, 7]);

function rangesOf(value: unknown, label: string): BusyRange[] {
  return recordsOf(value, label).map((row) => ({
    from: requiredInstant(row["startsAt"], `${label}.startsAt`),
    until: requiredInstant(row["endsAt"], `${label}.endsAt`),
  }));
}

/** A `calendar_free_busy` result. */
export function freeBusyOf(value: unknown): FreeBusy[] {
  return recordsOf(value, "calendar_free_busy").map((row) => {
    const tz = optionalText(row["tz"]);

    const hours =
      row["workingHours"] === null || row["workingHours"] === undefined
        ? undefined
        : rangesOf(row["workingHours"], "workingHours");

    return {
      userId: textOf(row["userId"]),
      busy: rangesOf(row["busy"], "busy"),
      outOfOffice: rangesOf(row["outOfOffice"], "outOfOffice"),
      focusTime: rangesOf(row["focusTime"], "focusTime"),
      ...(hours === undefined ? {} : { workingHours: hours }),
      ...(tz === undefined ? {} : { tz }),
    };
  });
}

/** A `list_calendar_working_hours` result. */
export function workingHoursOf(value: unknown): WorkingHours[] {
  return recordsOf(value, "list_calendar_working_hours").map((row) => ({
    userId: textOf(row["userId"]),
    tz: optionalText(row["tz"]) ?? "UTC",
    hours: recordsOf(row["hours"], "hours").flatMap((hour) => {
      const weekday = Number(hour["weekday"]);

      if (!WEEKDAYS.has(weekday)) {
        return [];
      }

      return [
        {
          // SAFETY: WEEKDAYS holds exactly the values of the weekday union.
          weekday: weekday as WeeklyHours["weekday"],
          start: textOf(hour["start"]),
          end: textOf(hour["end"]),
        },
      ];
    }),
  }));
}

const ms = (instant: Temporal.Instant): number => instant.epochMilliseconds;

/** Sorted, merged ranges. */
function merge(ranges: readonly BusyRange[]): BusyRange[] {
  const sorted = ranges
    .filter((range) => ms(range.until) > ms(range.from))
    .toSorted((a, b) => ms(a.from) - ms(b.from));

  const merged: BusyRange[] = [];

  for (const range of sorted) {
    const last = merged.at(-1);

    if (last !== undefined && ms(range.from) <= ms(last.until)) {
      if (ms(range.until) > ms(last.until)) {
        merged[merged.length - 1] = { from: last.from, until: range.until };
      }
    } else {
      merged.push(range);
    }
  }

  return merged;
}

/** `ranges` minus `cut`, both merged. */
function subtract(
  ranges: readonly BusyRange[],
  cut: readonly BusyRange[],
): BusyRange[] {
  const result: BusyRange[] = [];

  for (const range of ranges) {
    let from = range.from;

    for (const block of cut) {
      if (ms(block.until) <= ms(from) || ms(block.from) >= ms(range.until)) {
        continue;
      }

      if (ms(block.from) > ms(from)) {
        result.push({ from, until: block.from });
      }

      if (ms(block.until) > ms(from)) {
        from = block.until;
      }
    }

    if (ms(from) < ms(range.until)) {
      result.push({ from, until: range.until });
    }
  }

  return result;
}

/** Where two merged range lists overlap. */
function intersect(
  a: readonly BusyRange[],
  b: readonly BusyRange[],
): BusyRange[] {
  const result: BusyRange[] = [];

  for (const left of a) {
    for (const right of b) {
      const from = ms(left.from) > ms(right.from) ? left.from : right.from;
      const until = ms(left.until) < ms(right.until) ? left.until : right.until;

      if (ms(until) > ms(from)) {
        result.push({ from, until });
      }
    }
  }

  return merge(result);
}

/**
 * The ranges in `range` when every member in `freeBusy` is free, for a "find a
 * time" view or a scheduling suggestion.
 */
export function commonFreeTime(
  freeBusy: readonly FreeBusy[],
  range: OccurrenceRange,
  options: CommonFreeTimeOptions = {},
): BusyRange[] {
  let free: BusyRange[] = [{ from: range.from, until: range.until }];

  for (const member of freeBusy) {
    free = subtract(free, merge(member.busy));

    if (options.workingHours !== false && member.workingHours !== undefined) {
      free = intersect(free, merge(member.workingHours));
    }
  }

  const minimum = options.minimum?.total({ unit: "milliseconds" }) ?? 0;

  return free.filter(
    (slot) => ms(slot.until) - ms(slot.from) >= Math.max(minimum, 1),
  );
}
