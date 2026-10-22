import type { RecordRef } from "../../schema/types.ts";
import type { TimeEntry } from "./time-tracking.ts";

import { nowInstant } from "../../core/temporal.ts";

/** The fields `toWeeklyGrid` reads from an entry. */
export type WeeklyGridEntry = Pick<
  TimeEntry,
  "id" | "startedAt" | "endedAt" | "billable"
> & { readonly subject?: RecordRef | undefined };

export interface WeeklyGridOptions<E extends WeeklyGridEntry> {
  /** Any day of the week; the grid starts on its Monday. */
  readonly week: Temporal.PlainDate;
  /**
   * The IANA zone days start in:
   * `blockConfig["time-tracking"].options.timeZone` from
   * `blocks.generated.ts`.
   */
  readonly timeZone: string;
  /** Where a running entry ends. Default: now. */
  readonly now?: Temporal.Instant;
  /** The row an entry adds to. Default: its subject and whether it bills. */
  readonly rowKey?: (entry: E) => string;
}

/** One day column, Monday first. */
export interface WeeklyGridDay {
  /** `YYYY-MM-DD`, for a column id or accessor. */
  readonly id: string;
  readonly date: Temporal.PlainDate;
  /** Seconds tracked that day across every row. */
  readonly seconds: number;
}

/** One row of the grid: the time one record (or key) took each day. */
export interface WeeklyGridRow {
  readonly id: string;
  /** The record of the row's first entry; `undefined` when it has none. */
  readonly subject: RecordRef | undefined;
  readonly billable: boolean;
  /** Seconds per day, Monday first. */
  readonly days: readonly number[];
  readonly seconds: number;
  readonly entryIds: readonly string[];
}

/** A week of entries as rows and day columns. */
export interface WeeklyGrid {
  readonly days: readonly WeeklyGridDay[];
  readonly rows: readonly WeeklyGridRow[];
  readonly seconds: number;
  readonly billableSeconds: number;
}

const defaultKey = (entry: WeeklyGridEntry): string =>
  `${entry.subject?.type ?? ""}:${entry.subject?.id ?? ""}:${String(entry.billable)}`;

interface MutableRow {
  readonly id: string;
  readonly entry: WeeklyGridEntry;
  readonly days: number[];
  readonly entryIds: string[];
}

/**
 * Time entries as a weekly grid: one row per record (or `rowKey`) with the
 * seconds of each day, the shape of a weekly timesheet Data Grid. An entry that
 * crosses midnight counts on each day it covers.
 */
export function toWeeklyGrid<E extends WeeklyGridEntry>(
  entries: readonly E[],
  options: WeeklyGridOptions<E>,
): WeeklyGrid {
  const monday = options.week.subtract({ days: options.week.dayOfWeek - 1 });

  const dates = Array.from({ length: 7 }, (_, day) =>
    monday.add({ days: day }),
  );

  const starts = [...dates, monday.add({ days: 7 })].map((date) =>
    date.toZonedDateTime(options.timeZone).toInstant(),
  );

  let now = options.now;
  const keyOf = options.rowKey ?? defaultKey;
  const rows = new Map<string, MutableRow>();
  const totals = Array.from({ length: 7 }, () => 0);
  let billable = 0;

  for (const entry of entries) {
    const end = entry.endedAt ?? (now ??= nowInstant());
    const key = keyOf(entry);
    let row = rows.get(key);
    let counted = false;

    for (let day = 0; day < 7; day += 1) {
      const from = maxInstant(entry.startedAt, starts[day]!);
      const to = minInstant(end, starts[day + 1]!);
      const seconds = Math.max(0, Math.round(from.until(to).total("seconds")));

      if (seconds === 0) {
        continue;
      }

      row ??= {
        id: key,
        entry,
        days: Array.from({ length: 7 }, () => 0),
        entryIds: [],
      };
      rows.set(key, row);
      row.days[day]! += seconds;
      totals[day]! += seconds;

      if (entry.billable) {
        billable += seconds;
      }

      if (!counted) {
        row.entryIds.push(entry.id);
      }

      counted = true;
    }
  }

  return {
    days: dates.map((date, day) => ({
      id: date.toString(),
      date,
      seconds: totals[day]!,
    })),
    rows: [...rows.values()].map((row) => ({
      id: row.id,
      subject: row.entry.subject,
      billable: row.entry.billable,
      days: row.days,
      seconds: row.days.reduce((sum, value) => sum + value, 0),
      entryIds: row.entryIds,
    })),
    seconds: totals.reduce((sum, value) => sum + value, 0),
    billableSeconds: billable,
  };
}

function maxInstant(
  a: Temporal.Instant,
  b: Temporal.Instant,
): Temporal.Instant {
  return a.epochNanoseconds >= b.epochNanoseconds ? a : b;
}

function minInstant(
  a: Temporal.Instant,
  b: Temporal.Instant,
): Temporal.Instant {
  return a.epochNanoseconds <= b.epochNanoseconds ? a : b;
}
