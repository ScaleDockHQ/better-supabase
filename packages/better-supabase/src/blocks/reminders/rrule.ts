import { temporal } from "../../core/temporal-required.ts";

/**
 * Expands an RFC 5545 recurrence rule on `Temporal.ZonedDateTime`, so a
 * local time stays on the same clock time across a daylight-saving change.
 * Covered parts: FREQ, INTERVAL, COUNT, UNTIL, BYDAY (with ordinals),
 * BYMONTHDAY, BYMONTH, BYSETPOS and WKST.
 */

const DAYS: Readonly<Record<string, number>> = {
  MO: 1,
  TU: 2,
  WE: 3,
  TH: 4,
  FR: 5,
  SA: 6,
  SU: 7,
};

const FREQS = ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"] as const;
type Frequency = (typeof FREQS)[number];

interface DayRule {
  readonly ordinal: number | undefined;
  readonly day: number;
}

interface Rule {
  readonly frequency: Frequency;
  readonly interval: number;
  readonly count: number | undefined;
  readonly until: Temporal.Instant | undefined;
  readonly byDay: readonly DayRule[];
  readonly byMonthDay: readonly number[];
  readonly byMonth: readonly number[];
  readonly bySetPos: readonly number[];
  readonly weekStart: number;
}

export interface ExpandInput {
  readonly dtstart: Temporal.ZonedDateTime;
  /** An `RRULE` value, with or without the `RRULE:` prefix. */
  readonly rrule?: string;
  /** CentraKit's column shape, used when `ruleFormat` is `columns`. */
  readonly columns?: {
    readonly frequency: "daily" | "weekly" | "monthly" | "yearly";
    readonly interval?: number;
    readonly weekDays?: readonly number[];
    readonly monthDay?: number;
    readonly monthWeekday?: number;
    readonly monthOrdinal?: number;
    readonly count?: number;
    readonly until?: Temporal.Instant;
  };
  /** Stops after this many occurrences. COUNT still wins when it is smaller. */
  readonly limit?: number;
}

const DAY_NAME = ["", "MO", "TU", "WE", "TH", "FR", "SA", "SU"] as const;

function part(text: string): Rule {
  const body = text.replace(/^RRULE:/i, "").trim();
  const fields = new Map(
    body.split(";").map((item) => {
      const eq = item.indexOf("=");
      return [item.slice(0, eq).toUpperCase(), item.slice(eq + 1)] as const;
    }),
  );
  const frequency = frequencyOf(fields.get("FREQ"));
  const interval = Number(fields.get("INTERVAL") ?? "1");
  if (!Number.isInteger(interval) || interval < 1) {
    throw new TypeError("INTERVAL must be a positive integer");
  }
  const countText = fields.get("COUNT");
  const count = countText === undefined ? undefined : Number(countText);
  if (count !== undefined && (!Number.isInteger(count) || count < 1)) {
    throw new TypeError("COUNT must be a positive integer");
  }
  const untilText = fields.get("UNTIL");
  const byDay = (fields.get("BYDAY") ?? "")
    .split(",")
    .filter(Boolean)
    .map(dayRule);
  return {
    frequency,
    interval,
    count,
    until: untilText === undefined ? undefined : until(untilText),
    byDay,
    byMonthDay: numbers(fields.get("BYMONTHDAY")),
    byMonth: numbers(fields.get("BYMONTH")),
    bySetPos: numbers(fields.get("BYSETPOS")),
    weekStart: DAYS[fields.get("WKST") ?? "MO"] ?? 1,
  };
}

function dayRule(text: string): DayRule {
  const match = /^([+-]?\d+)?(MO|TU|WE|TH|FR|SA|SU)$/.exec(text.toUpperCase());
  if (!match) throw new TypeError(`BYDAY value ${text} is not a weekday`);
  const day = DAYS[match[2] ?? ""];
  if (day === undefined)
    throw new TypeError(`BYDAY value ${text} is not a weekday`);
  return {
    ordinal: match[1] === undefined ? undefined : Number(match[1]),
    day,
  };
}

function numbers(text: string | undefined): readonly number[] {
  if (text === undefined || text === "") return [];
  return text.split(",").map((item) => {
    const value = Number(item);
    if (!Number.isInteger(value) || value === 0) {
      throw new TypeError(`recurrence part ${item} is not a non-zero integer`);
    }
    return value;
  });
}

function until(text: string): Temporal.Instant {
  const match = /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$/.exec(text);
  if (!match) throw new TypeError("UNTIL must be a UTC date-time");
  const [, year, month, day, hour, minute, second] = match;
  return temporal().Instant.from(
    `${year}-${month}-${day}T${hour}:${minute}:${second}Z`,
  );
}

const COLUMN_FREQUENCY = {
  daily: "DAILY",
  weekly: "WEEKLY",
  monthly: "MONTHLY",
  yearly: "YEARLY",
} as const;

function frequencyOf(value: string | undefined): Frequency {
  if (
    value === "DAILY" ||
    value === "WEEKLY" ||
    value === "MONTHLY" ||
    value === "YEARLY"
  ) {
    return value;
  }
  throw new TypeError(
    "an RRULE needs FREQ of DAILY, WEEKLY, MONTHLY or YEARLY",
  );
}

function fromColumns(columns: NonNullable<ExpandInput["columns"]>): Rule {
  const frequency = COLUMN_FREQUENCY[columns.frequency];
  const byDay: DayRule[] =
    columns.monthWeekday === undefined
      ? (columns.weekDays ?? []).map((day) => ({ ordinal: undefined, day }))
      : [
          {
            ordinal: columns.monthOrdinal,
            day: columns.monthWeekday,
          },
        ];
  return {
    frequency,
    interval: columns.interval ?? 1,
    count: columns.count,
    until: columns.until,
    byDay,
    byMonthDay: columns.monthDay === undefined ? [] : [columns.monthDay],
    byMonth: [],
    bySetPos: [],
    weekStart: 1,
  };
}

function at(
  date: Temporal.PlainDate,
  start: Temporal.ZonedDateTime,
): Temporal.ZonedDateTime {
  return date.toZonedDateTime({
    timeZone: start.timeZoneId,
    plainTime: start.toPlainTime(),
  });
}

function monthDay(
  year: number,
  month: number,
  which: number,
): Temporal.PlainDate | undefined {
  const dates = temporal().PlainDate;
  const length = dates.from({ year, month, day: 1 }).daysInMonth;
  const day = which > 0 ? which : length + which + 1;
  if (day < 1 || day > length) return undefined;
  return dates.from({ year, month, day });
}

function nthWeekday(
  year: number,
  month: number,
  ordinal: number,
  weekday: number,
): Temporal.PlainDate | undefined {
  const dates = temporal().PlainDate;
  const first = dates.from({ year, month, day: 1 });
  const length = first.daysInMonth;
  if (ordinal > 0) {
    const delta = (weekday - first.dayOfWeek + 7) % 7;
    const day = 1 + delta + (ordinal - 1) * 7;
    if (day > length) return undefined;
    return dates.from({ year, month, day });
  }
  const last = dates.from({ year, month, day: length });
  const delta = (last.dayOfWeek - weekday + 7) % 7;
  const day = length - delta + (ordinal + 1) * 7;
  if (day < 1) return undefined;
  return dates.from({ year, month, day });
}

function weekOf(
  date: Temporal.PlainDate,
  weekStart: number,
): Temporal.PlainDate {
  const delta = (date.dayOfWeek - weekStart + 7) % 7;
  return date.subtract({ days: delta });
}

function periodDates(
  start: Temporal.ZonedDateTime,
  rule: Rule,
  index: number,
): Temporal.PlainDate[] {
  const anchor = start.toPlainDate();
  if (rule.frequency === "DAILY") {
    const date = anchor.add({ days: index * rule.interval });
    if (
      rule.byDay.length > 0 &&
      !rule.byDay.some((item) => item.day === date.dayOfWeek)
    ) {
      return [];
    }
    return [date];
  }
  if (rule.frequency === "WEEKLY") {
    const week = weekOf(anchor, rule.weekStart).add({
      weeks: index * rule.interval,
    });
    const days =
      rule.byDay.length === 0
        ? [{ ordinal: undefined, day: anchor.dayOfWeek }]
        : rule.byDay;
    return days.map((item) =>
      week.add({ days: (item.day - rule.weekStart + 7) % 7 }),
    );
  }
  const moved =
    rule.frequency === "MONTHLY"
      ? anchor.add({ months: index * rule.interval })
      : anchor.add({ years: index * rule.interval });
  const months = rule.byMonth.length === 0 ? [moved.month] : rule.byMonth;
  const dates: Temporal.PlainDate[] = [];
  for (const month of months) {
    const year = rule.frequency === "YEARLY" ? moved.year : moved.year;
    if (rule.byDay.some((item) => item.ordinal !== undefined)) {
      for (const item of rule.byDay) {
        if (item.ordinal === undefined) continue;
        const date = nthWeekday(year, month, item.ordinal, item.day);
        if (date) dates.push(date);
      }
      continue;
    }
    if (rule.byDay.length > 0) {
      const datesOf = temporal().PlainDate;
      const length = datesOf.from({ year, month, day: 1 }).daysInMonth;
      for (let day = 1; day <= length; day += 1) {
        const date = datesOf.from({ year, month, day });
        if (rule.byDay.some((item) => item.day === date.dayOfWeek))
          dates.push(date);
      }
    } else if (rule.byMonthDay.length > 0) {
      for (const which of rule.byMonthDay) {
        const date = monthDay(year, month, which);
        if (date) dates.push(date);
      }
    } else {
      const date = monthDay(year, month, moved.day);
      if (date) dates.push(date);
    }
  }
  return dates;
}

function applySetPos(
  dates: readonly Temporal.PlainDate[],
  positions: readonly number[],
): Temporal.PlainDate[] {
  const sorted = dates.toSorted((a, b) => temporal().PlainDate.compare(a, b));
  const picked = new Set<string>();
  for (const position of positions) {
    const index = position > 0 ? position - 1 : sorted.length + position;
    const date = sorted[index];
    if (date) picked.add(date.toString());
  }
  return sorted.filter((date) => picked.has(date.toString()));
}

/** The occurrences of a rule, in order, starting at `dtstart` when it matches. */
export function expandRule(input: ExpandInput): Temporal.ZonedDateTime[] {
  if (input.rrule === undefined && input.columns === undefined) {
    throw new TypeError("expandRule needs an rrule or columns");
  }
  const rule =
    input.columns === undefined
      ? part(input.rrule ?? "")
      : fromColumns(input.columns);
  const start = input.dtstart;
  const cap = Math.min(rule.count ?? input.limit ?? 366, input.limit ?? 366);
  const found: Temporal.ZonedDateTime[] = [];
  for (let index = 0; found.length < cap && index < 4000; index += 1) {
    let dates = periodDates(start, rule, index);
    if (rule.bySetPos.length > 0) dates = applySetPos(dates, rule.bySetPos);
    const time = temporal();
    const ordered = dates.toSorted((a, b) => time.PlainDate.compare(a, b));
    for (const date of ordered) {
      const when = at(date, start);
      if (time.ZonedDateTime.compare(when, start) < 0) continue;
      if (
        rule.until !== undefined &&
        time.Instant.compare(when.toInstant(), rule.until) > 0
      ) {
        return found;
      }
      found.push(when);
      if (found.length >= cap) return found;
    }
  }
  return found;
}

/** A weekday name for a column-format rule, 1 (Monday) through 7 (Sunday). */
export function weekdayName(day: number): string {
  const name = DAY_NAME[day];
  if (name === undefined || name === "") {
    throw new TypeError("weekday must be 1 (Monday) through 7 (Sunday)");
  }
  return name;
}
