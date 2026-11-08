import { isIsoDate } from "./deadlines-evaluate.ts";
// The rule set version validator. It imports only the values and the
// evaluator's date parser, so the client entry can run it; the SQL function
// `validate_deadline_rules` in `deadlines-validator.ts` finds the same
// problems in the same order.
import {
  DEADLINE_ADJUSTMENTS,
  DEADLINE_NAME,
  EXCEPTION_RESULTS,
  has,
  isRecord,
  META_LIMIT,
  NOTE_LIMIT,
  OBSERVED_FALLS_ON,
  OBSERVED_MOVES,
  OFFSET_LIMIT,
  OFFSET_UNITS,
  PART_STATUSES,
  ROLL_DAYS,
  RULE_KEY,
  WEEKDAYS,
} from "./deadlines-values.ts";

type Json = Readonly<Record<string, unknown>>;

const list = (values: readonly string[]): string => values.join(", ");

/** Length in code points, as `char_length` counts it. */
const characters = (value: string): number =>
  value.length - (value.match(/[\u{10000}-\u{10FFFF}]/gu)?.length ?? 0);

const keysOf = (value: Json): string[] => Object.keys(value).toSorted();

/** Bytes of a value's jsonb text: JSON with a space after each `:` and `,`. */
function jsonbBytes(value: unknown): number {
  let separators = 0;

  const walk = (node: unknown): void => {
    const children = Array.isArray(node)
      ? node
      : isRecord(node)
        ? Object.values(node)
        : [];

    separators +=
      Math.max(children.length - 1, 0) + (isRecord(node) ? children.length : 0);

    for (const child of children) {
      walk(child);
    }
  };

  walk(value);

  return new TextEncoder().encode(JSON.stringify(value)).length + separators;
}

function badMeta(value: unknown): boolean {
  return !isRecord(value) || jsonbBytes(value) > META_LIMIT;
}

function isText(value: unknown, max: number): boolean {
  return typeof value === "string" && characters(value) <= max;
}

function isName(value: unknown): value is string {
  return typeof value === "string" && DEADLINE_NAME.test(value);
}

function isWhole(value: unknown, min: number, max: number): value is number {
  return (
    typeof value === "number" &&
    Number.isInteger(value) &&
    value >= min &&
    value <= max
  );
}

function oneOf(values: readonly string[], value: unknown): boolean {
  return values.some((entry) => entry === value);
}

function badCitation(value: unknown): boolean {
  return (
    !isRecord(value) ||
    typeof value["reference"] !== "string" ||
    value["reference"].trim() === ""
  );
}

function isDate(value: unknown): value is string {
  return isIsoDate(value);
}

function codes(value: unknown): boolean {
  return (
    Array.isArray(value) &&
    value.length > 0 &&
    value.every((entry) => typeof entry === "string" && entry !== "") &&
    new Set(value).size === value.length
  );
}

function badCondition(value: unknown, nonEmpty: boolean): boolean {
  if (!isRecord(value)) {
    return true;
  }

  const entries = Object.entries(value);

  return (
    (nonEmpty && entries.length === 0) ||
    entries.some(
      ([fact, expected]) =>
        !isName(fact) ||
        !(
          typeof expected === "boolean" ||
          (typeof expected === "string" && expected !== "") ||
          codes(expected)
        ),
    )
  );
}

function countsBefore(node: unknown): boolean {
  if (Array.isArray(node)) {
    return node.some(countsBefore);
  }

  return (
    isRecord(node) &&
    ("before" in node || Object.values(node).some(countsBefore))
  );
}

function countIssues(count: unknown, at: string, inside: boolean): string[] {
  if (!isRecord(count)) {
    return [`${at} must be a count`];
  }

  const issues: string[] = [];
  const { from, before, n, unit } = count;

  if (
    (from === undefined) === (before === undefined) ||
    (from !== undefined && !isName(from)) ||
    (before !== undefined && !isName(before))
  ) {
    issues.push(`${at} counts from or before one fact`);
  }

  if (n !== undefined && !isWhole(n, 0, OFFSET_LIMIT)) {
    issues.push(`${at} n is a whole number from 0 to ${OFFSET_LIMIT}`);
  }

  if (unit !== undefined && !oneOf(OFFSET_UNITS, unit)) {
    issues.push(`${at} unit is ${list(OFFSET_UNITS)}`);
  }

  if (n !== undefined && unit === undefined) {
    issues.push(`${at} n needs a unit`);
  }

  if (from !== undefined && n === undefined) {
    issues.push(`${at} from needs n`);
  }

  if (
    count["day_of_month"] !== undefined &&
    (!isWhole(count["day_of_month"], 1, 28) || unit !== "months")
  ) {
    issues.push(`${at} day_of_month is 1 to 28 with unit months`);
  }

  if (count["each"] !== undefined) {
    if (inside) {
      issues.push(`${at} each is not allowed inside a combinator`);
    } else if (
      count["each"] !== "furnishing_month" ||
      from === undefined ||
      n === undefined
    ) {
      issues.push(`${at} each is furnishing_month on a count from a fact`);
    }
  }

  return issues;
}

const COMBINATORS = ["first_of", "earlier_of", "later_of"] as const;

function deadlineIssues(deadline: unknown, at: string): string[] {
  if (deadline === "none") {
    return [];
  }

  const notADeadline = `${at} deadline is none, a count, or ${list(COMBINATORS)} with at least two counts`;

  if (!isRecord(deadline)) {
    return [notADeadline];
  }

  const combinator = COMBINATORS.find((key) => has(deadline, key));

  if (combinator === undefined) {
    return countIssues(deadline, `${at} deadline`, false);
  }

  const counts = deadline[combinator];

  if (
    Object.keys(deadline).length !== 1 ||
    !Array.isArray(counts) ||
    counts.length < 2
  ) {
    return [notADeadline];
  }

  return counts.flatMap((count, index) =>
    countIssues(count, `${at} deadline ${combinator} ${index + 1}`, true),
  );
}

function appliesIssues(value: unknown, at: string): string[] {
  if (!isRecord(value)) {
    return [`${at} applies must be an object`];
  }

  const issues: string[] = [];
  let regimes = 0;

  for (const fact of keysOf(value)) {
    const entry = value[fact];

    if (!DEADLINE_NAME.test(fact)) {
      issues.push(`${at} applies ${fact} is not a fact name`);
    } else if (isRecord(entry)) {
      regimes += 1;

      const { from, before } = entry;

      if (
        keysOf(entry).some((key) => key !== "from" && key !== "before") ||
        (from === undefined && before === undefined) ||
        (from !== undefined && !isDate(from)) ||
        (before !== undefined && !isDate(before)) ||
        (isDate(from) && isDate(before) && from >= before)
      ) {
        issues.push(`${at} applies ${fact} is a date range from before before`);
      }
    } else if (!(entry === "present" || entry === "absent" || codes(entry))) {
      issues.push(
        `${at} applies ${fact} is a list of codes, present or absent`,
      );
    }
  }

  if (regimes > 1) {
    issues.push(`${at} selects by one date at most`);
  }

  return issues;
}

function exceptionIssues(exceptions: unknown, at: string): string[] {
  if (!Array.isArray(exceptions)) {
    return [`${at} exceptions must be a list`];
  }

  const issues: string[] = [];
  const names = new Set<string>();

  for (const [index, exception] of exceptions.entries()) {
    const here = `${at} exception ${index + 1}`;

    if (!isRecord(exception)) {
      issues.push(`${here} must be an object`);
      continue;
    }

    const { name } = exception;

    if (!isName(name)) {
      issues.push(`${here} needs a name in lower case letters, digits and _`);
    } else if (names.has(name)) {
      issues.push(`${here} repeats the name ${name}`);
    } else {
      names.add(name);
    }

    if (badCondition(exception["when"], true)) {
      issues.push(`${here} when is a non-empty condition`);
    }

    if (
      exception["unless"] !== undefined &&
      badCondition(exception["unless"], false)
    ) {
      issues.push(`${here} unless is a condition`);
    }

    if (!oneOf(EXCEPTION_RESULTS, exception["result"])) {
      issues.push(`${here} result is ${list(EXCEPTION_RESULTS)}`);
    }

    if (
      exception["remedy"] !== undefined &&
      !isText(exception["remedy"], 500)
    ) {
      issues.push(`${here} remedy is text of at most 500 characters`);
    }

    if (
      exception["note"] !== undefined &&
      !isText(exception["note"], NOTE_LIMIT)
    ) {
      issues.push(`${here} note is text of at most ${NOTE_LIMIT} characters`);
    }

    if (
      exception["status"] !== undefined &&
      !oneOf(PART_STATUSES, exception["status"])
    ) {
      issues.push(`${here} status is ${list(PART_STATUSES)}`);
    }

    if (badCitation(exception["citation"])) {
      issues.push(`${here} needs a citation with a reference`);
    }
  }

  return issues;
}

function requiresCycle(
  requires: ReadonlyMap<string, readonly string[]>,
  start: string,
): string | undefined {
  return (requires.get(start) ?? []).find((next) => {
    const seen = new Set<string>();
    const queue = [next];

    while (queue.length > 0) {
      const key = queue.shift() ?? "";

      if (key === start) {
        return true;
      }

      if (!seen.has(key)) {
        seen.add(key);
        queue.push(...(requires.get(key) ?? []));
      }
    }

    return false;
  });
}

function groupIssues(groups: readonly unknown[]): string[] {
  const issues: string[] = [];
  const keys = new Set<string>();

  for (const [index, group] of groups.entries()) {
    const at = `group ${index + 1}`;

    if (!isRecord(group)) {
      issues.push(`${at} must be an object`);
      continue;
    }

    const { key } = group;

    if (!isName(key)) {
      issues.push(`${at} needs a key in lower case letters, digits and _`);
    } else if (keys.has(key)) {
      issues.push(`${at} repeats the key ${key}`);
    } else {
      keys.add(key);
    }

    if (group["title"] !== undefined && !isText(group["title"], 200)) {
      issues.push(`${at} title is text of at most 200 characters`);
    }

    if (badCitation(group["citation"])) {
      issues.push(`${at} needs a citation with a reference`);
    }

    if (group["meta"] !== undefined && badMeta(group["meta"])) {
      issues.push(
        `${at} meta must be an object of at most ${META_LIMIT} bytes`,
      );
    }
  }

  const requires = new Map<string, readonly string[]>();

  for (const [index, group] of groups.entries()) {
    if (!isRecord(group) || group["requires"] === undefined) {
      continue;
    }

    const named: unknown = group["requires"];
    const valid: string[] = [];

    if (
      Array.isArray(named) &&
      named.every((key) => {
        const ok =
          typeof key === "string" && keys.has(key) && key !== group["key"];

        if (ok) {
          valid.push(key);
        }

        return ok;
      })
    ) {
      if (typeof group["key"] === "string") {
        requires.set(group["key"], valid);
      }
    } else {
      issues.push(`group ${index + 1} requires is a list of other group keys`);
    }
  }

  for (const [index, group] of groups.entries()) {
    const start = isRecord(group) ? group["key"] : undefined;

    const through =
      typeof start === "string" ? requiresCycle(requires, start) : undefined;

    if (through !== undefined) {
      issues.push(`group ${index + 1} requires itself through ${through}`);
    }
  }

  return issues;
}

function ruleIssues(
  rules: readonly unknown[],
  groups: readonly unknown[],
): string[] {
  const issues: string[] = [];
  const keys = new Set<string>();

  const known = new Set(
    groups.flatMap((group) =>
      isRecord(group) && typeof group["key"] === "string" ? [group["key"]] : [],
    ),
  );

  for (const [index, rule] of rules.entries()) {
    const at = `rule ${index + 1}`;

    if (!isRecord(rule)) {
      issues.push(`${at} must be an object`);
      continue;
    }

    const { key } = rule;

    if (typeof key !== "string" || !RULE_KEY.test(key)) {
      issues.push(`${at} needs a key in lower case letters, digits and _`);
    } else if (keys.has(key)) {
      issues.push(`${at} repeats the key ${key}`);
    } else {
      keys.add(key);
    }

    if (typeof rule["group"] !== "string" || !known.has(rule["group"])) {
      issues.push(`${at} needs a group that the version lists`);
    }

    if (rule["title"] !== undefined && !isText(rule["title"], 200)) {
      issues.push(`${at} title is text of at most 200 characters`);
    }

    if (rule["status"] !== undefined && !oneOf(PART_STATUSES, rule["status"])) {
      issues.push(`${at} status is ${list(PART_STATUSES)}`);
    }

    if (
      rule["adjust"] !== undefined &&
      !oneOf(DEADLINE_ADJUSTMENTS, rule["adjust"])
    ) {
      issues.push(`${at} adjust is ${list(DEADLINE_ADJUSTMENTS)}`);
    }

    if (
      rule["adjust"] === "next_business_day" &&
      countsBefore(rule["deadline"])
    ) {
      issues.push(
        `${at} adjust next_business_day never follows a before count`,
      );
    }

    if (
      rule["required"] !== undefined &&
      typeof rule["required"] !== "boolean"
    ) {
      issues.push(`${at} required is true or false`);
    }

    if (badCitation(rule["citation"])) {
      issues.push(`${at} needs a citation with a reference`);
    }

    if (rule["applies"] !== undefined) {
      issues.push(...appliesIssues(rule["applies"], at));
    }

    if (rule["deadline"] !== undefined) {
      issues.push(...deadlineIssues(rule["deadline"], at));
    }

    if (rule["exceptions"] !== undefined) {
      issues.push(...exceptionIssues(rule["exceptions"], at));
    }

    if (rule["meta"] !== undefined && badMeta(rule["meta"])) {
      issues.push(
        `${at} meta must be an object of at most ${META_LIMIT} bytes`,
      );
    }
  }

  return issues;
}

function holidayIssues(holiday: unknown, at: string): string[] {
  if (!isRecord(holiday)) {
    return [`${at} must be an object`];
  }

  const issues: string[] = [];
  const { name, date, observed } = holiday;

  if (typeof name !== "string" || name === "" || !isText(name, 200)) {
    issues.push(`${at} needs a name of at most 200 characters`);
  }

  const fixed =
    isRecord(date) &&
    keysOf(date).join(",") === "day,month" &&
    isWhole(date["month"], 1, 12) &&
    isWhole(date["day"], 1, 31);

  const nth =
    isRecord(date) &&
    keysOf(date).join(",") === "month,nth,weekday" &&
    isWhole(date["month"], 1, 12) &&
    oneOf(WEEKDAYS, date["weekday"]) &&
    (date["nth"] === "last" || isWhole(date["nth"], 1, 5));

  if (!fixed && !nth) {
    issues.push(`${at} date is a month and day, or a month, weekday and nth`);
  }

  if (badCitation(holiday["citation"])) {
    issues.push(`${at} needs a citation with a reference`);
  }

  if (observed === undefined) {
    return issues;
  }

  if (!Array.isArray(observed)) {
    return [...issues, `${at} observed must be a list`];
  }

  for (const [index, entry] of observed.entries()) {
    if (
      !isRecord(entry) ||
      !oneOf(OBSERVED_FALLS_ON, entry["falls_on"]) ||
      !oneOf(OBSERVED_MOVES, entry["observe"]) ||
      (entry["replaces"] !== undefined &&
        typeof entry["replaces"] !== "boolean") ||
      badCitation(entry["citation"])
    ) {
      issues.push(
        `${at} observed ${index + 1} needs falls_on, observe and a citation`,
      );
    }
  }

  return issues;
}

function countingIssues(counting: Json): string[] {
  const issues: string[] = [];

  if (counting["roll_to"] !== "next_business_day") {
    issues.push("counting roll_to is next_business_day");
  }

  const when = counting["roll_when"];

  if (
    !Array.isArray(when) ||
    when.length === 0 ||
    !when.every((day) => oneOf(ROLL_DAYS, day)) ||
    new Set(when).size !== when.length
  ) {
    issues.push(`counting roll_when is a non-empty list of ${list(ROLL_DAYS)}`);
  }

  const holidays = counting["holidays"];

  if (Array.isArray(holidays)) {
    for (const [index, holiday] of holidays.entries()) {
      issues.push(...holidayIssues(holiday, `counting holiday ${index + 1}`));
    }
  } else if (holidays !== undefined) {
    issues.push("counting holidays must be a list");
  }

  if (counting["citation"] !== undefined && badCitation(counting["citation"])) {
    issues.push("counting citation needs a reference");
  }

  if (
    counting["status"] !== undefined &&
    !oneOf(PART_STATUSES, counting["status"])
  ) {
    issues.push(`counting status is ${list(PART_STATUSES)}`);
  }

  return issues;
}

/**
 * The problems of a rule set version's content, empty when it can be saved. The
 * SQL function `validate_deadline_rules` finds the same ones, in the same
 * order.
 */
export function validateRuleVersion(content: unknown): readonly string[] {
  if (!isRecord(content)) {
    return ["a rule set version is an object with rules and groups"];
  }

  const { rules, groups, counting, meta } = content;
  const empty: string[] = [];

  if (!Array.isArray(rules) || rules.length === 0) {
    empty.push("a rule set version needs a non-empty list of rules");
  }

  if (!Array.isArray(groups) || groups.length === 0) {
    empty.push("a rule set version needs a non-empty list of groups");
  }

  if (!Array.isArray(rules) || !Array.isArray(groups) || empty.length > 0) {
    return empty;
  }

  const issues = [...groupIssues(groups), ...ruleIssues(rules, groups)];

  if (isRecord(counting)) {
    issues.push(...countingIssues(counting));
  } else if (counting !== undefined && counting !== null) {
    issues.push("counting must be an object");
  }

  if (meta !== undefined && meta !== null && badMeta(meta)) {
    issues.push(`meta must be an object of at most ${META_LIMIT} bytes`);
  }

  return issues;
}
