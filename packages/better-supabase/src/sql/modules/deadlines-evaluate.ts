// The deadlines evaluator: a rule set version against a subject's facts. It
// imports only `deadlines-values.ts`, so the client entry can run it, and every
// function has a SQL twin in `deadlines-evaluator.ts` with the same semantics;
// the golden fixtures in `tests/fixtures/deadlines` run both.
import type {
  Condition,
  ConditionValue,
  DateRegime,
  DeadlineAdjustment,
  DeadlineBasis,
  DeadlineCount,
  DeadlineCounting,
  DeadlineException,
  DeadlineFacts,
  DeadlineGroup,
  DeadlineGroupResult,
  DeadlineHoliday,
  DeadlineResult,
  DeadlineReview,
  DeadlineRule,
  DeadlineSpec,
  OBSERVED_FALLS_ON,
  OBSERVED_MOVES,
  RuleVersionContent,
} from "./deadlines-values.ts";

import {
  FIRST_FURNISHING_FACT,
  has,
  ISO_DATE,
  LAST_FURNISHING_FACT,
  WEEKDAYS,
} from "./deadlines-values.ts";

const DAY_MS = 86_400_000;

type Verdict = true | false | "unknown";

interface Judged {
  readonly verdict: Verdict;
  readonly asks: readonly string[];
}

type Candidate =
  | {
      readonly state: "dated";
      readonly due: number;
      readonly fact: string;
      readonly anchor: number;
    }
  | { readonly state: "skipped" }
  | { readonly state: "unanswered"; readonly asks: readonly string[] };

type Counting = DeadlineCounting | undefined;

// ── dates on epoch days ──────────────────────────────────────────────────────

function fromParts(year: number, month: number, day: number): number {
  const date = new Date(0);

  date.setUTCFullYear(year, month - 1, day);

  return Math.round(date.getTime() / DAY_MS);
}

function parts(days: number): readonly [number, number, number] {
  const date = new Date(days * DAY_MS);

  return [date.getUTCFullYear(), date.getUTCMonth() + 1, date.getUTCDate()];
}

/** Days since the epoch of an ISO date, or `undefined` when it isn't one. */
function parseDate(value: unknown): number | undefined {
  if (typeof value !== "string") {
    return undefined;
  }

  const match = ISO_DATE.exec(value);

  if (match === null) {
    return undefined;
  }

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const days = fromParts(year, month, day);
  const [y, m, d] = parts(days);

  // Year 0 is no date in Postgres either.
  return year >= 1 && y === year && m === month && d === day ? days : undefined;
}

/** Whether a value is a valid ISO date string. */
export function isIsoDate(value: unknown): value is string {
  return parseDate(value) !== undefined;
}

function format(days: number): string {
  return new Date(days * DAY_MS).toISOString().slice(0, 10);
}

/** ISO day of the week: Monday 1 to Sunday 7. */
function isoDow(days: number): number {
  return ((((days + 3) % 7) + 7) % 7) + 1;
}

function daysInMonth(year: number, month: number): number {
  return fromParts(year, month + 1, 1) - fromParts(year, month, 1);
}

function addMonths(days: number, months: number): number {
  const [year, month, day] = parts(days);
  const total = year * 12 + month - 1 + months;
  const y = Math.floor(total / 12);
  const m = total - y * 12 + 1;

  return fromParts(y, m, Math.min(day, daysInMonth(y, m)));
}

function monthStart(days: number): number {
  const [year, month] = parts(days);

  return fromParts(year, month, 1);
}

// ── holidays and business days ───────────────────────────────────────────────

function holidayListed(
  holiday: DeadlineHoliday,
  year: number,
): number | undefined {
  const { date } = holiday;
  const last = daysInMonth(year, date.month);

  if ("day" in date) {
    return date.day > last ? undefined : fromParts(year, date.month, date.day);
  }

  const wanted = WEEKDAYS.indexOf(date.weekday) + 1;

  if (date.nth === "last") {
    const end = fromParts(year, date.month, last);

    return end - ((isoDow(end) - wanted + 7) % 7);
  }

  const first = fromParts(year, date.month, 1);
  const day = first + ((wanted - isoDow(first) + 7) % 7) + (date.nth - 1) * 7;

  return day - first < last ? day : undefined;
}

function fallsOn(
  days: number,
  on: (typeof OBSERVED_FALLS_ON)[number],
): boolean {
  switch (on) {
    case "saturday": {
      return isoDow(days) === 6;
    }

    case "sunday": {
      return isoDow(days) === 7;
    }

    case "other_than_sunday": {
      return isoDow(days) !== 7;
    }

    default: {
      const exhaustive: never = on;

      return exhaustive;
    }
  }
}

function observedDay(
  days: number,
  observe: (typeof OBSERVED_MOVES)[number],
): number {
  const before = (weekday: number): number =>
    days - (((isoDow(days) - weekday + 6) % 7) + 1);

  const after = (weekday: number): number =>
    days + (((weekday - isoDow(days) + 6) % 7) + 1);

  switch (observe) {
    case "preceding_friday": {
      return before(5);
    }

    case "following_monday": {
      return after(1);
    }

    case "preceding_sunday": {
      return before(7);
    }

    case "following_sunday": {
      return after(7);
    }

    default: {
      const exhaustive: never = observe;

      return exhaustive;
    }
  }
}

/** The days the holidays make holidays for the dates listed in a year. */
function holidaysOf(
  holidays: readonly DeadlineHoliday[],
  year: number,
): number[] {
  return holidays.flatMap((holiday) => {
    const listed = holidayListed(holiday, year);

    if (listed === undefined) {
      return [];
    }

    const moved = (holiday.observed ?? []).filter((entry) =>
      fallsOn(listed, entry.falls_on),
    );

    const observed = moved.map((entry) => observedDay(listed, entry.observe));

    return moved.some((entry) => entry.replaces === true)
      ? observed
      : [listed, ...observed];
  });
}

function isHoliday(counting: Counting, days: number): boolean {
  const holidays = counting?.holidays ?? [];

  if (holidays.length === 0) {
    return false;
  }

  const [year] = parts(days);

  return [year - 1, year, year + 1].some((y) =>
    holidaysOf(holidays, y).includes(days),
  );
}

/**
 * Whether an ISO date is a holiday of a counting block: listed in its year, or
 * observed from a date listed in the year before or after. The SQL function
 * `deadline_is_holiday` answers the same.
 */
export function deadlineIsHoliday(counting: Counting, date: string): boolean {
  const days = parseDate(date);

  return days !== undefined && isHoliday(counting, days);
}

function approved(counting: Counting): boolean {
  return (
    counting !== undefined && (counting.status ?? "approved") === "approved"
  );
}

/** Not a weekend, and not a holiday of an approved counting block. */
function businessDay(counting: Counting, days: number): boolean {
  return isoDow(days) < 6 && !(approved(counting) && isHoliday(counting, days));
}

/** Moves a last day forward while it falls on a day the block rolls past. */
function roll(counting: Counting, days: number): number {
  if (counting === undefined || !approved(counting)) {
    return days;
  }

  const when = counting.roll_when;
  let current = days;

  while (
    (when.includes("saturday") && isoDow(current) === 6) ||
    (when.includes("sunday") && isoDow(current) === 7) ||
    (when.includes("holiday") && isHoliday(counting, current))
  ) {
    current += 1;
  }

  return current;
}

function adjust(
  counting: Counting,
  days: number,
  how: DeadlineAdjustment,
): number {
  if (how === "none") {
    return days;
  }

  const step = how === "next_business_day" ? 1 : -1;
  let current = days;

  while (!businessDay(counting, current)) {
    current += step;
  }

  return current;
}

// ── counts ───────────────────────────────────────────────────────────────────

function addCountDays(
  anchor: number,
  count: DeadlineCount,
  counting: Counting,
): number {
  const n = (count.n ?? 0) * (count.before === undefined ? 1 : -1);

  switch (count.unit) {
    case undefined:
    case "days": {
      return anchor + n;
    }

    case "months": {
      if (count.day_of_month === undefined) {
        return addMonths(anchor, n);
      }

      const [year, month] = parts(addMonths(monthStart(anchor), n));

      return fromParts(
        year,
        month,
        Math.min(count.day_of_month, daysInMonth(year, month)),
      );
    }

    case "business_days": {
      const step = n < 0 ? -1 : 1;
      let current = anchor;
      let left = Math.abs(n);

      while (left > 0) {
        current += step;

        if (businessDay(counting, current)) {
          left -= 1;
        }
      }

      return current;
    }

    default: {
      const exhaustive: never = count.unit;

      return exhaustive;
    }
  }
}

/**
 * The date a count yields from an ISO anchor date, before any roll, or null
 * when the anchor isn't a date. The SQL function `deadline_add` returns the
 * same.
 */
export function deadlineAdd(
  anchor: string,
  count: DeadlineCount,
  counting?: DeadlineCounting | null,
): string | null {
  const days = parseDate(anchor);

  return days === undefined
    ? null
    : format(addCountDays(days, count, counting ?? undefined));
}

function candidate(
  count: DeadlineCount,
  facts: DeadlineFacts,
  counting: Counting,
): Candidate {
  const fact = count.from ?? count.before ?? "";

  if (!has(facts, fact)) {
    return { state: "unanswered", asks: [fact] };
  }

  if (facts[fact] === null) {
    return { state: "skipped" };
  }

  const anchor = parseDate(facts[fact]);

  return anchor === undefined
    ? { state: "unanswered", asks: [fact] }
    : {
        state: "dated",
        due: addCountDays(anchor, count, counting),
        fact,
        anchor,
      };
}

function countsOf(deadline: DeadlineSpec): readonly DeadlineCount[] {
  if (deadline === "none") {
    return [];
  }

  if ("first_of" in deadline) {
    return deadline.first_of;
  }

  if ("earlier_of" in deadline) {
    return deadline.earlier_of;
  }

  if ("later_of" in deadline) {
    return deadline.later_of;
  }

  return [deadline];
}

interface Outcome {
  readonly result: "due" | "unknown" | "pending" | "undated";
  readonly due: number | null;
  readonly asks: readonly string[];
  readonly basis: DeadlineBasis | null;
}

const asksOf = (candidates: readonly Candidate[]): string[] =>
  candidates.flatMap((c) => (c.state === "unanswered" ? c.asks : []));

function skippedFrom(
  counts: readonly DeadlineCount[],
  candidates: readonly Candidate[],
): string[] {
  return counts.flatMap((count, index) =>
    count.from !== undefined && candidates[index]?.state === "skipped"
      ? [count.from]
      : [],
  );
}

function outcomeOf(
  deadline: DeadlineSpec | undefined,
  facts: DeadlineFacts,
  counting: Counting,
): Outcome {
  if (deadline === undefined || deadline === "none") {
    return { result: "undated", due: null, asks: [], basis: null };
  }

  const counts = countsOf(deadline);
  const candidates = counts.map((count) => candidate(count, facts, counting));
  const asks = asksOf(candidates);

  const undated: Outcome = {
    result: asks.length > 0 ? "unknown" : "pending",
    due: null,
    asks,
    basis: null,
  };

  const dated = candidates.flatMap((c) => (c.state === "dated" ? [c.due] : []));

  if ("first_of" in deadline) {
    const index = candidates.findIndex((c) => c.state === "dated");
    const taken = candidates[index];

    return taken?.state === "dated"
      ? {
          result: "due",
          due: taken.due,
          asks: asksOf(candidates.slice(0, index)),
          basis: {
            anchor: { fact: taken.fact, date: format(taken.anchor) },
            without: skippedFrom(counts, candidates),
          },
        }
      : undated;
  }

  if ("earlier_of" in deadline) {
    return dated.length === 0
      ? undated
      : {
          result: "due",
          due: Math.min(...dated),
          asks,
          basis: { anchor: null, without: skippedFrom(counts, candidates) },
        };
  }

  if ("later_of" in deadline) {
    return dated.length === 0 || asks.length > 0
      ? undated
      : {
          result: "due",
          due: Math.max(...dated),
          asks: [],
          basis: { anchor: null, without: [] },
        };
  }

  const [only] = candidates;

  return only?.state === "dated"
    ? {
        result: "due",
        due: only.due,
        asks: [],
        basis: {
          anchor: { fact: only.fact, date: format(only.anchor) },
          without: [],
        },
      }
    : undated;
}

/** A deadline with a count before a fact never rolls. */
function rolls(deadline: DeadlineSpec | undefined): boolean {
  return (
    deadline !== undefined &&
    countsOf(deadline).every((count) => count.before === undefined)
  );
}

function monthlyCount(
  deadline: DeadlineSpec | undefined,
): DeadlineCount | undefined {
  return deadline !== undefined &&
    deadline !== "none" &&
    !("first_of" in deadline) &&
    !("earlier_of" in deadline) &&
    !("later_of" in deadline) &&
    deadline.each === "furnishing_month"
    ? deadline
    : undefined;
}

/**
 * A monthly count's months as their first days, or what it waits for before it
 * has any. The months run from the first furnishing through the last or, while
 * furnishing goes on, through the month of `asOf` and one ahead.
 */
function periodsOf(
  facts: DeadlineFacts,
  asOf: number,
): { readonly months: readonly number[]; readonly asks: readonly string[] } {
  if (facts[FIRST_FURNISHING_FACT] === null) {
    return { months: [], asks: [] };
  }

  const first = parseDate(facts[FIRST_FURNISHING_FACT]);

  if (first === undefined) {
    return { months: [], asks: [FIRST_FURNISHING_FACT] };
  }

  const last = parseDate(facts[LAST_FURNISHING_FACT]);
  const ongoing = last === undefined || last > asOf;
  const end = monthStart(ongoing ? asOf : last);
  const months: number[] = [];
  let month = monthStart(first);

  do {
    months.push(month);
    month = addMonths(month, 1);
  } while (month <= end);

  if (ongoing) {
    months.push(month);
  }

  return { months, asks: [] };
}

// ── conditions and selection ─────────────────────────────────────────────────

/** A fact as an enum code: a string, or a number as its decimal text. */
function code(value: unknown): string | undefined {
  if (typeof value === "string") {
    return value;
  }

  return typeof value === "number" ? String(value) : undefined;
}

function judgeEntry(
  facts: DeadlineFacts,
  fact: string,
  expected: ConditionValue,
): Verdict {
  if (!has(facts, fact)) {
    return "unknown";
  }

  const value = facts[fact];

  if (expected === "present" || expected === "absent") {
    return (value !== null) === (expected === "present");
  }

  if (value === null) {
    return "unknown";
  }

  if (typeof expected === "boolean") {
    return value === expected;
  }

  const text = code(value);

  return typeof expected === "string"
    ? text === expected
    : text !== undefined && expected.includes(text);
}

/** Three-valued AND over a condition's entries. */
function judge(condition: Condition | undefined, facts: DeadlineFacts): Judged {
  const asks: string[] = [];

  for (const [fact, expected] of Object.entries(condition ?? {})) {
    const verdict = judgeEntry(facts, fact, expected);

    if (verdict === false) {
      return { verdict: false, asks: [] };
    }

    if (verdict === "unknown") {
      asks.push(fact);
    }
  }

  return { verdict: asks.length > 0 ? "unknown" : true, asks };
}

function isRegime(value: ConditionValue | DateRegime): value is DateRegime {
  return !(
    typeof value === "string" ||
    typeof value === "boolean" ||
    Array.isArray(value)
  );
}

interface Regime {
  readonly fact: string;
  readonly from: string | null;
}

type Selection =
  | {
      readonly kind: "rule";
      readonly rule: DeadlineRule;
      readonly regime: Regime | null;
    }
  | { readonly kind: "asks"; readonly asks: readonly string[] }
  | { readonly kind: "not_covered" };

/**
 * Whether a rule applies: its membership entries first, then its date regime. A
 * regime whose date is unknown applies, and names the fact.
 */
function applies(
  rule: DeadlineRule,
  facts: DeadlineFacts,
): Judged & { readonly regime: Regime | null } {
  const membership: Record<string, ConditionValue> = {};
  let range: [string, DateRegime] | undefined;

  for (const [fact, value] of Object.entries(rule.applies ?? {})) {
    if (isRegime(value)) {
      range = [fact, value];
    } else {
      membership[fact] = value;
    }
  }

  const judged = judge(membership, facts);

  if (judged.verdict !== true || range === undefined) {
    return { ...judged, regime: null };
  }

  const [fact, { from, before }] = range;
  const date = parseDate(facts[fact]);

  if (date === undefined) {
    return { verdict: true, asks: [], regime: { fact, from: from ?? null } };
  }

  const value = format(date);

  return {
    verdict:
      (from === undefined || value >= from) &&
      (before === undefined || value < before),
    asks: [],
    regime: null,
  };
}

/** The first rule of a group that applies, unless an earlier one is open. */
function selectRule(
  rules: readonly DeadlineRule[],
  facts: DeadlineFacts,
): Selection {
  const asks = new Set<string>();

  for (const rule of rules) {
    const judged = applies(rule, facts);

    if (judged.verdict === true && asks.size === 0) {
      return { kind: "rule", rule, regime: judged.regime };
    }

    if (judged.verdict === "unknown") {
      for (const fact of judged.asks) {
        asks.add(fact);
      }
    }
  }

  return asks.size > 0
    ? { kind: "asks", asks: [...asks] }
    : { kind: "not_covered" };
}

// ── one group ────────────────────────────────────────────────────────────────

const sorted = (names: readonly string[]): string[] =>
  [...new Set(names)].toSorted();

function base(group: DeadlineGroup): DeadlineGroupResult {
  return {
    group: group.key,
    ruleKey: null,
    period: null,
    result: "not_covered",
    dueOn: null,
    provisional: false,
    missing: [],
    exception: null,
    review: [],
    basis: null,
    deadline: null,
    citation: group.citation,
  };
}

interface Refused {
  readonly exception: DeadlineException & {
    readonly result: "barred" | "not_applicable" | "not_required";
  };
}

/**
 * The exceptions of a rule in order: the first settled one whose `when` holds
 * and whose `unless` doesn't decides. An unsettled one is carried for review,
 * and an open one asks its facts.
 */
function tripped(
  rule: DeadlineRule,
  facts: DeadlineFacts,
): {
  readonly refused: Refused | null;
  readonly unsettled: readonly DeadlineReview[];
  readonly asks: readonly string[];
} {
  const asks: string[] = [];
  const unsettled: DeadlineReview[] = [];

  for (const exception of rule.exceptions ?? []) {
    const when = judge(exception.when, facts);

    const unless: Judged =
      exception.unless === undefined
        ? { verdict: false, asks: [] }
        : judge(exception.unless, facts);

    if (when.verdict === false || unless.verdict === true) {
      continue;
    }

    if (when.verdict === true && unless.verdict === false) {
      const { result } = exception;

      if (
        result !== "review_required" &&
        exception.status !== "review_required"
      ) {
        return {
          refused: { exception: { ...exception, result } },
          unsettled,
          asks,
        };
      }

      unsettled.push({
        kind: "exception",
        name: exception.name,
        citation: exception.citation,
        ...(exception.note === undefined ? {} : { note: exception.note }),
      });
      continue;
    }

    asks.push(...when.asks, ...unless.asks);
  }

  return { refused: null, unsettled, asks };
}

function evaluateGroup(
  content: RuleVersionContent,
  group: DeadlineGroup,
  facts: DeadlineFacts,
  asOf: number,
): DeadlineGroupResult[] {
  const empty = base(group);

  const selection = selectRule(
    content.rules.filter((rule) => rule.group === group.key),
    facts,
  );

  if (selection.kind === "asks") {
    return [{ ...empty, result: "unknown", missing: sorted(selection.asks) }];
  }

  if (selection.kind === "not_covered") {
    return [empty];
  }

  const { rule, regime } = selection;
  const status = rule.status ?? "approved";

  const regimeMarks: DeadlineReview[] =
    regime === null ? [] : [{ kind: "regime", ...regime }];

  const ruleMarks: DeadlineReview[] =
    status === "approved" ? [] : [{ kind: "rule", status }];

  const selected: DeadlineGroupResult = {
    ...empty,
    ruleKey: rule.key,
    deadline: rule.deadline ?? null,
    citation: rule.citation,
  };

  const finish = (
    result: DeadlineGroupResult,
    asks: readonly string[],
    review: readonly DeadlineReview[],
  ): DeadlineGroupResult => {
    const missing = sorted([
      ...(regime === null ? [] : [regime.fact]),
      ...asks,
    ]);

    return {
      ...result,
      missing,
      provisional: result.result !== "unknown" && missing.length > 0,
      review: [...regimeMarks, ...review, ...ruleMarks],
    };
  };

  if (rule.required === false) {
    return [
      finish(
        { ...selected, result: "not_required", citation: group.citation },
        [],
        [],
      ),
    ];
  }

  const exceptions = tripped(rule, facts);

  if (exceptions.refused !== null) {
    const { exception } = exceptions.refused;

    return [
      finish(
        {
          ...selected,
          result: exception.result,
          exception: {
            name: exception.name,
            citation: exception.citation,
            ...(exception.remedy === undefined
              ? {}
              : { remedy: exception.remedy }),
            ...(exception.note === undefined ? {} : { note: exception.note }),
          },
        },
        exceptions.asks,
        [],
      ),
    ];
  }

  const counting = content.counting ?? undefined;

  const countingMarks: DeadlineReview[] =
    counting === undefined || approved(counting)
      ? []
      : [{ kind: "counting", status: counting.status ?? "approved" }];

  const dated = (days: number): string =>
    format(
      adjust(
        counting,
        rolls(rule.deadline) ? roll(counting, days) : days,
        rule.adjust ?? "none",
      ),
    );

  const monthly = monthlyCount(rule.deadline);

  if (monthly !== undefined) {
    const { months, asks } = periodsOf(facts, asOf);

    if (months.length === 0) {
      return [
        finish(
          { ...selected, result: asks.length > 0 ? "unknown" : "pending" },
          [...exceptions.asks, ...asks],
          exceptions.unsettled,
        ),
      ];
    }

    return months.map((start) =>
      finish(
        {
          ...selected,
          result: "due",
          period: format(start).slice(0, 7),
          dueOn: dated(addCountDays(start, monthly, counting)),
          basis: {
            anchor: { fact: monthly.from ?? "", date: format(start) },
            without: [],
          },
        },
        exceptions.asks,
        [...exceptions.unsettled, ...countingMarks],
      ),
    );
  }

  const outcome = outcomeOf(rule.deadline, facts, counting);

  return [
    finish(
      {
        ...selected,
        result: outcome.result,
        dueOn: outcome.due === null ? null : dated(outcome.due),
        basis: outcome.basis,
      },
      [...exceptions.asks, ...outcome.asks],
      outcome.result === "due"
        ? [...exceptions.unsettled, ...countingMarks]
        : exceptions.unsettled,
    ),
  ];
}

const OPEN_RESULTS: ReadonlySet<DeadlineResult> = new Set([
  "due",
  "unknown",
  "pending",
  "undated",
]);

/**
 * A group that requires a barred group is barred with it, to a fixed point.
 * Only a group without a refusal of its own falls.
 */
function cascade(
  results: Map<string, readonly DeadlineGroupResult[]>,
  groups: readonly DeadlineGroup[],
): void {
  let changed = true;

  while (changed) {
    changed = false;

    for (const group of groups) {
      const [first] = results.get(group.key) ?? [];

      if (first === undefined || !OPEN_RESULTS.has(first.result)) {
        continue;
      }

      const barring = (group.requires ?? [])
        .map((key) => results.get(key)?.[0])
        .find((result) => result?.result === "barred");

      if (barring?.exception === undefined || barring.exception === null) {
        continue;
      }

      results.set(group.key, [
        {
          ...first,
          period: null,
          result: "barred",
          dueOn: null,
          provisional: false,
          missing: [],
          basis: null,
          review: first.review.filter(
            (mark) => mark.kind !== "exception" && mark.kind !== "counting",
          ),
          exception: {
            name: barring.exception.name,
            citation: barring.exception.citation,
            note: `falls with ${barring.group}`,
          },
        },
      ]);
      changed = true;
    }
  }
}

/** A group and every group it requires, transitively. */
function closure(groups: readonly DeadlineGroup[], key: string): Set<string> {
  const keys = new Set<string>();
  const queue = [key];

  while (queue.length > 0) {
    const next = queue.shift() ?? "";

    if (!keys.has(next)) {
      keys.add(next);
      queue.push(...(groups.find((g) => g.key === next)?.requires ?? []));
    }
  }

  return keys;
}

function today(): string {
  return new Date().toISOString().slice(0, 10);
}

/**
 * Evaluates a rule set version for a subject's facts: one result per group in
 * the version's order (one per month for a periodic rule), or only `group`'s.
 * `asOf` (today by default) ends a periodic rule's months while furnishing goes
 * on. The SQL function `evaluate_deadlines` returns the same results.
 */
export function evaluateVersion(
  content: RuleVersionContent,
  facts: DeadlineFacts,
  asOf: string = today(),
  group?: string,
): readonly DeadlineGroupResult[] {
  const day = parseDate(asOf);

  if (day === undefined) {
    throw new RangeError(`asOf is not an ISO date: ${asOf}`);
  }

  const wanted =
    group === undefined ? undefined : closure(content.groups, group);

  const evaluated = content.groups.filter(
    (g) => wanted === undefined || wanted.has(g.key),
  );

  const results = new Map(
    evaluated.map((g) => [g.key, evaluateGroup(content, g, facts, day)]),
  );

  cascade(results, evaluated);

  return evaluated
    .filter((g) => group === undefined || g.key === group)
    .flatMap((g) => results.get(g.key) ?? []);
}
