// The deadlines block's fixed values and its rule evaluator. This file imports
// nothing, so the client entry can run the same evaluation as the SQL function
// `evaluate_deadline_rule` (ADR 0242).

/** The states of a version of a rule set. */
export const RULE_VERSION_STATUSES = ["draft", "approved"] as const;

/** What a deadline row holds: a date, or the facts it still waits for. */
export const DEADLINE_RESULTS = ["due", "unknown"] as const;

/** Where a deadline stands: pending until an action satisfies it. */
export const DEADLINE_STATES = ["pending", "satisfied"] as const;

export const OFFSET_UNITS = ["days", "business_days", "months"] as const;

export type OffsetUnit = (typeof OFFSET_UNITS)[number];

/** How a date that lands on a weekend moves. */
export const DEADLINE_ADJUSTMENTS = [
  "none",
  "next_business_day",
  "previous_business_day",
] as const;

export type DeadlineAdjustment = (typeof DEADLINE_ADJUSTMENTS)[number];

/** The largest offset a rule may carry, in its unit. */
export const OFFSET_LIMIT = 3650;

/** A name of a fact or a rule: lower case, digits and `_`. */
const DEADLINE_NAME_PATTERN: RegExp = /^[a-z][a-z0-9_]{0,62}$/u;

/** Where a rule comes from. */
export interface DeadlineCitation {
  /** A statute or regulation reference, such as `Section 12(3)`. */
  readonly reference: string;
  readonly url?: string;
  /** The quoted text the rule follows. */
  readonly text?: string;
}

/** One rule: a date computed from an anchor fact. */
export interface DeadlineRule {
  /** The name of the rule inside its rule set. */
  readonly key: string;
  readonly title?: string;
  /** The fact that holds the date the deadline counts from. */
  readonly anchor: string;
  readonly offset: { readonly amount: number; readonly unit: OffsetUnit };
  /** Moves a result that lands on a weekend; `none` by default. */
  readonly adjust?: DeadlineAdjustment;
  /** Facts that must be present next to the anchor. */
  readonly requires?: readonly string[];
  readonly citation: DeadlineCitation;
}

/** The result of one evaluation. */
export type DeadlineEvaluation =
  | { readonly status: "due"; readonly dueOn: string }
  | { readonly status: "unknown"; readonly missing: readonly string[] };

const DATE = /^(\d{4})-(\d{2})-(\d{2})$/u;
const DAY_MS = 86_400_000;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Days since the epoch of an ISO date, or `undefined` when it isn't a date. */
function parseDate(value: unknown): number | undefined {
  if (typeof value !== "string") {
    return undefined;
  }

  const match = DATE.exec(value.trim());

  if (match === null) {
    return undefined;
  }

  const [year, month, day] = [match[1], match[2], match[3]].map(Number);
  const ms = Date.UTC(year ?? 0, (month ?? 1) - 1, day ?? 1);
  const check = new Date(ms);

  return check.getUTCFullYear() === year &&
    check.getUTCMonth() === (month ?? 1) - 1 &&
    check.getUTCDate() === day
    ? ms / DAY_MS
    : undefined;
}

function format(days: number): string {
  return new Date(days * DAY_MS).toISOString().slice(0, 10);
}

function weekend(days: number): boolean {
  const day = new Date(days * DAY_MS).getUTCDay();

  return day === 0 || day === 6;
}

function addMonths(days: number, months: number): number {
  const date = new Date(days * DAY_MS);
  const total = date.getUTCFullYear() * 12 + date.getUTCMonth() + months;
  const year = Math.floor(total / 12);
  const month = total - year * 12;
  const last = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();

  return Date.UTC(year, month, Math.min(date.getUTCDate(), last)) / DAY_MS;
}

function present(facts: Readonly<Record<string, unknown>>, name: string) {
  const value = facts[name];

  return value !== undefined && value !== null && String(value).trim() !== "";
}

/**
 * Evaluates a rule against facts: `due` with an ISO date, or `unknown` with the
 * facts that are missing, the anchor first. Weekends are Saturday and Sunday;
 * holidays are not modeled. The SQL function `evaluate_deadline_rule` returns
 * the same result.
 */
export function evaluateDeadlineRule(
  rule: DeadlineRule,
  facts: Readonly<Record<string, unknown>>,
): DeadlineEvaluation {
  const anchor = parseDate(facts[rule.anchor]);
  const missing: string[] = [];

  for (const name of new Set([rule.anchor, ...(rule.requires ?? [])])) {
    if (
      !present(facts, name) ||
      (name === rule.anchor && anchor === undefined)
    ) {
      missing.push(name);
    }
  }

  if (missing.length > 0 || anchor === undefined) {
    return { status: "unknown", missing };
  }

  const { amount, unit } = rule.offset;
  let due = anchor;

  if (unit === "days") {
    due += amount;
  } else if (unit === "months") {
    due = addMonths(anchor, amount);
  } else {
    const step = amount < 0 ? -1 : 1;

    for (let left = Math.abs(amount); left > 0; left -= 1) {
      due += step;

      while (weekend(due)) {
        due += step;
      }
    }
  }

  const adjust = rule.adjust ?? "none";

  if (adjust !== "none") {
    const step = adjust === "next_business_day" ? 1 : -1;

    while (weekend(due)) {
      due += step;
    }
  }

  return { status: "due", dueOn: format(due) };
}

/**
 * The problems of a rule list, empty when it is valid. The SQL function
 * `validate_deadline_rules` finds the same ones.
 */
export function validateDeadlineRules(rules: unknown): readonly string[] {
  if (!Array.isArray(rules) || rules.length === 0) {
    return ["a rule set version needs a non-empty list of rules"];
  }

  const issues: string[] = [];
  const keys = new Set<string>();

  for (const [index, rule] of rules.entries()) {
    const at = `rule ${index + 1}`;

    if (!isRecord(rule)) {
      issues.push(`${at} must be an object`);
      continue;
    }

    const key = rule["key"];

    if (typeof key !== "string" || !DEADLINE_NAME_PATTERN.test(key)) {
      issues.push(`${at} needs a key in lower case letters, digits and _`);
    } else if (keys.has(key)) {
      issues.push(`${at} repeats the key ${key}`);
    } else {
      keys.add(key);
    }

    const anchor = rule["anchor"];

    if (typeof anchor !== "string" || !DEADLINE_NAME_PATTERN.test(anchor)) {
      issues.push(`${at} needs an anchor fact name`);
    }

    const offset = rule["offset"];

    if (
      !isRecord(offset) ||
      typeof offset["amount"] !== "number" ||
      !Number.isInteger(offset["amount"]) ||
      Math.abs(offset["amount"]) > OFFSET_LIMIT ||
      !OFFSET_UNITS.some((unit) => unit === offset["unit"])
    ) {
      issues.push(
        `${at} needs an offset of a whole amount up to ${OFFSET_LIMIT} in ${OFFSET_UNITS.join(", ")}`,
      );
    }

    const adjust = rule["adjust"];

    if (
      adjust !== undefined &&
      !DEADLINE_ADJUSTMENTS.some((value) => value === adjust)
    ) {
      issues.push(`${at} adjust is ${DEADLINE_ADJUSTMENTS.join(", ")}`);
    }

    const requires = rule["requires"];

    if (
      requires !== undefined &&
      (!Array.isArray(requires) ||
        !requires.every(
          (name) =>
            typeof name === "string" && DEADLINE_NAME_PATTERN.test(name),
        ))
    ) {
      issues.push(`${at} requires is a list of fact names`);
    }

    const citation = rule["citation"];

    if (
      !isRecord(citation) ||
      typeof citation["reference"] !== "string" ||
      citation["reference"].trim() === ""
    ) {
      issues.push(`${at} needs a citation with a reference`);
    }
  }

  return issues;
}
