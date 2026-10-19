import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import type { SearchParam, TaskRow } from "./project-types";

const DateParam = v.pipe(v.string(), v.isoDate());

const MonthParam = v.pipe(v.string(), v.regex(/^\d{4}-(0[1-9]|1[0-2])$/));

/** The days a timeline or gantt shows. */
export const WINDOW_DAYS = 28;

/** The first day of `?month=YYYY-MM`, else of the month `today` is in. */
export function firstOfMonth(
  value: SearchParam,
  today: Temporal.PlainDate,
): Temporal.PlainDate {
  const parsed = v.safeParse(MonthParam, value);

  return parsed.success
    ? Temporal.PlainDate.from(`${parsed.output}-01`)
    : today.with({ day: 1 });
}

/** The Monday-first weeks that cover the month, as 7-day rows. */
export function weeksOf(first: Temporal.PlainDate): Temporal.PlainDate[][] {
  const start = first.subtract({ days: first.dayOfWeek - 1 });
  const last = first.add({ months: 1 }).subtract({ days: 1 });
  const end = last.add({ days: 7 - last.dayOfWeek });
  const days = Math.round(start.until(end).total({ unit: "days" })) + 1;

  return Array.from({ length: days / 7 }, (_, week) =>
    Array.from({ length: 7 }, (_, day) => start.add({ days: week * 7 + day })),
  );
}

/** The Monday on or before `?from=YYYY-MM-DD`, else before `today`. */
export function windowStart(
  value: SearchParam,
  today: Temporal.PlainDate,
): Temporal.PlainDate {
  const parsed = v.safeParse(DateParam, value);
  const day = parsed.success ? Temporal.PlainDate.from(parsed.output) : today;

  return day.subtract({ days: day.dayOfWeek - 1 });
}

export interface Span {
  /** Zero-based day in the window the bar starts on. */
  readonly start: number;
  /** Days the bar covers inside the window, at least one. */
  readonly length: number;
}

/**
 * Where a task's bar falls in the window. A task with one date is a one-day
 * bar; a task with neither, or outside the window, has no bar.
 */
export function spanOf(task: TaskRow, from: Temporal.PlainDate): Span | null {
  const first = task.startsOn ?? task.dueOn;
  const last = task.dueOn ?? task.startsOn;

  if (first === null || last === null) {
    return null;
  }

  const dayOf = (date: string) =>
    Math.round(
      from.until(Temporal.PlainDate.from(date)).total({ unit: "days" }),
    );

  const start = Math.max(dayOf(first), 0);
  const end = Math.min(dayOf(last), WINDOW_DAYS - 1);

  return end < start ? null : { start, length: end - start + 1 };
}
