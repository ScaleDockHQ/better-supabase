import { temporal } from "../../core/temporal-required.ts";

interface CronFields {
  readonly minutes: readonly number[];
  readonly hours: readonly number[];
  readonly days: ReadonlySet<number>;
  readonly months: ReadonlySet<number>;
  readonly weekdays: ReadonlySet<number>;
  readonly daysRestricted: boolean;
  readonly weekdaysRestricted: boolean;
}

const MACROS: Readonly<Record<string, string>> = {
  "@yearly": "0 0 1 1 *",
  "@annually": "0 0 1 1 *",
  "@monthly": "0 0 1 * *",
  "@weekly": "0 0 * * 0",
  "@daily": "0 0 * * *",
  "@midnight": "0 0 * * *",
  "@hourly": "0 * * * *",
};

const MONTHS = [
  "jan",
  "feb",
  "mar",
  "apr",
  "may",
  "jun",
  "jul",
  "aug",
  "sep",
  "oct",
  "nov",
  "dec",
];
const WEEKDAYS = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];

/** Replaces `JAN` or `MON` style names with their numbers. */
function named(text: string, names: readonly string[], first: number): string {
  return text.replaceAll(/[a-z]{3}/gi, (name) => {
    const index = names.indexOf(name.toLowerCase());
    return index === -1 ? name : String(index + first);
  });
}

const INTERVAL = /^(\d+)\s+(second|minute|hour)s?$/i;

/** Gives up when no minute matches within this many days (`0 0 30 2 *`). */
const SEARCH_DAYS = 366 * 5;

function invalid(expression: string, reason: string): TypeError {
  return new TypeError(`Invalid cron "${expression}": ${reason}`);
}

function field(
  expression: string,
  text: string,
  min: number,
  max: number,
): number[] {
  const values = new Set<number>();
  for (const part of text.split(",")) {
    const match = /^(\*|\d+(?:-\d+)?)(?:\/(\d+))?$/.exec(part);
    if (!match) throw invalid(expression, `"${part}" is not a cron field`);
    const [, range = "", stepText] = match;
    const step = stepText === undefined ? 1 : Number(stepText);
    let from = min;
    let to = max;
    if (range !== "*") {
      const [start = "", end] = range.split("-");
      from = Number(start);
      to =
        end === undefined ? (stepText === undefined ? from : max) : Number(end);
    }
    if (step < 1 || from < min || to > max || from > to) {
      throw invalid(
        expression,
        `"${part}" is outside ${String(min)}-${String(max)}`,
      );
    }
    for (let value = from; value <= to; value += step) values.add(value);
  }
  return [...values].toSorted((a, b) => a - b);
}

function parse(expression: string): CronFields {
  const source = MACROS[expression.trim().toLowerCase()] ?? expression;
  const parts = source.trim().split(/\s+/);
  if (parts.length !== 5) {
    throw invalid(
      expression,
      "expected 5 fields (minute hour day month weekday)",
    );
  }
  const [minute = "", hour = "", day = "", monthText = "", weekdayText = ""] =
    parts;
  const month = named(monthText, MONTHS, 1);
  const weekday = named(weekdayText, WEEKDAYS, 0);
  return {
    minutes: field(expression, minute, 0, 59),
    hours: field(expression, hour, 0, 23),
    days: new Set(field(expression, day, 1, 31)),
    months: new Set(field(expression, month, 1, 12)),
    // Cron's 7 is Sunday too; Temporal's dayOfWeek is 1 (Monday) to 7 (Sunday).
    weekdays: new Set(
      field(expression, weekday, 0, 7).map((value) =>
        value === 0 ? 7 : value,
      ),
    ),
    daysRestricted: day !== "*",
    weekdaysRestricted: weekday !== "*",
  };
}

function dayMatches(fields: CronFields, date: Temporal.PlainDate): boolean {
  if (!fields.months.has(date.month)) return false;
  const day = fields.days.has(date.day);
  const weekday = fields.weekdays.has(date.dayOfWeek);
  if (fields.daysRestricted && fields.weekdaysRestricted) return day || weekday;
  if (fields.daysRestricted) return day;
  if (fields.weekdaysRestricted) return weekday;
  return true;
}

/** The first matching minute of `date` after `after`, from `start` on its first day. */
function firstRunOn(
  fields: CronFields,
  date: Temporal.PlainDate,
  start: Temporal.PlainDateTime | undefined,
  timeZone: string,
  after: Temporal.Instant,
): Temporal.Instant | undefined {
  for (const hour of fields.hours) {
    if (start && hour < start.hour) continue;
    for (const minute of fields.minutes) {
      if (hour === start?.hour && minute < start.minute) continue;
      const instant = date
        .toPlainDateTime({ hour, minute })
        .toZonedDateTime(timeZone, { disambiguation: "compatible" })
        .toInstant();
      if (temporal().Instant.compare(instant, after) > 0) return instant;
    }
  }
  return undefined;
}

/**
 * Throws a `TypeError` unless `expression` is a schedule `nextCronRun`
 * understands: five cron fields, a macro such as `@daily`, or an interval
 * such as `30 seconds`.
 */
export function assertCron(expression: string): void {
  if (!INTERVAL.test(expression.trim())) parse(expression);
}

/**
 * The first run of `expression` after `after`, in `timeZone`.
 *
 * Accepts five cron fields (lists, ranges and steps; a restricted day of
 * month and day of week match either, as in cron), the macros `@hourly`,
 * `@daily`, `@weekly`, `@monthly` and `@yearly`, and intervals such as
 * `30 seconds`, `5 minutes` or `2 hours`, counted from `after`. A local time
 * that a DST change skips runs at the same offset after the gap.
 */
export function nextCronRun(
  expression: string,
  timeZone: string,
  after: Temporal.Instant,
): Temporal.Instant {
  const interval = INTERVAL.exec(expression.trim());
  if (interval) {
    const amount = Number(interval[1]);
    if (amount < 1) throw invalid(expression, "the interval must be positive");
    const unit = interval[2]!.toLowerCase();
    return after.add(
      unit === "second"
        ? { seconds: amount }
        : unit === "minute"
          ? { minutes: amount }
          : { hours: amount },
    );
  }
  const fields = parse(expression);
  const start = after
    .toZonedDateTimeISO(timeZone)
    .toPlainDateTime()
    .round({ smallestUnit: "minute", roundingMode: "floor" })
    .add({ minutes: 1 });
  let date = start.toPlainDate();
  for (let offset = 0; offset < SEARCH_DAYS; offset += 1) {
    const found =
      dayMatches(fields, date) &&
      firstRunOn(
        fields,
        date,
        offset === 0 ? start : undefined,
        timeZone,
        after,
      );
    if (found) return found;
    date = date.add({ days: 1 });
  }
  throw invalid(expression, "it never matches a date");
}
