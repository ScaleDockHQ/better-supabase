/// <reference lib="esnext.temporal" />

import type {
  FilterClock,
  FilterDateValue,
  FilterFieldType,
  FilterNode,
  FilterQuery,
  FilterRule,
} from "./filter-query.ts";

import { isRecord } from "../core/guards.ts";
import { optionalTemporal, TEMPORAL_MISSING } from "../core/temporal.ts";
import { dateBounds, NEGATIVE } from "./filter-query.ts";

/**
 * A field a filter tree can test on a plain record. `FilterFieldInfo` from a
 * list definition fits; the rules block builds these from its field catalog.
 */
export interface FilterRecordField {
  readonly id: string;
  readonly type: FilterFieldType;
  /** The record key the value is read from, dotted for a nested value. */
  readonly column: string;
  readonly columnMeta: {
    /** The Postgres type: `date`, `timestamp` and `timestamptz` pick how dates compare. */
    readonly type: string;
    readonly nullable: boolean;
  };
}

/**
 * The outcome of a tree on one record. `results` holds every rule and group
 * that took part, by node id: `null` when a comparison met a missing value,
 * which SQL treats as unknown and a match treats as false.
 */
export interface FilterEvaluation {
  readonly matched: boolean;
  readonly results: Readonly<Record<string, boolean | null>>;
}

type Truth = boolean | null;

function read(record: unknown, column: string): unknown {
  let value: unknown = record;

  for (const key of column.split(".")) {
    if (!isRecord(value)) {
      return undefined;
    }

    value = value[key];
  }

  return value;
}

const missing = (value: unknown): value is null | undefined =>
  value === null || value === undefined;

function numberOf(value: unknown): number | null {
  if (typeof value === "number") {
    return Number.isFinite(value) ? value : null;
  }

  if (typeof value === "bigint") {
    return Number(value);
  }

  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);

    return Number.isFinite(parsed) ? parsed : null;
  }

  return null;
}

function textOf(value: unknown): string | null {
  if (typeof value === "string") {
    return value;
  }

  if (
    typeof value === "number" ||
    typeof value === "bigint" ||
    typeof value === "boolean"
  ) {
    return String(value);
  }

  return null;
}

function booleanOf(value: unknown): boolean | null {
  if (typeof value === "boolean") {
    return value;
  }

  if (value === "true" || value === "false") {
    return value === "true";
  }

  return null;
}

/** A value and a bound in one ordering: epoch milliseconds or ISO text. */
function dateKey(kind: string, value: unknown): number | string | null {
  if (kind === "timestamptz") {
    if (value instanceof Date) {
      return value.getTime();
    }

    const T = optionalTemporal();

    if (T !== undefined && value instanceof T.Instant) {
      return value.epochMilliseconds;
    }

    if (typeof value === "string") {
      const ms = Date.parse(value);

      return Number.isNaN(ms) ? null : ms;
    }

    return null;
  }

  const text =
    value instanceof Date
      ? value.toISOString().replace(/Z$/, "")
      : typeof value === "string"
        ? value
        : isRecord(value) && typeof value.toString === "function"
          ? String(value)
          : null;

  if (text === null) {
    return null;
  }

  if (kind === "date") {
    return text.slice(0, 10);
  }

  const T = optionalTemporal();

  if (T === undefined) {
    throw new TypeError(TEMPORAL_MISSING);
  }

  try {
    return T.PlainDateTime.from(text.replace(" ", "T")).toString({
      fractionalSecondDigits: 9,
    });
  } catch {
    return null;
  }
}

function boundKey(kind: string, bound: string): number | string {
  if (kind === "timestamptz") {
    return Date.parse(bound);
  }

  const key = dateKey(kind, bound);

  return key ?? bound;
}

function dateTruth(
  field: FilterRecordField,
  operator: string,
  operand: unknown,
  value: unknown,
  clock: FilterClock,
): Truth {
  const kind = field.columnMeta.type;
  const at = dateKey(kind, value);

  if (at === null) {
    return null;
  }

  if (operator === "between") {
    // SAFETY: checkFilterQuery accepted a range of two date values.
    const [from, to] = operand as readonly [FilterDateValue, FilterDateValue];

    return (
      at >= boundKey(kind, dateBounds(field, from, clock).start) &&
      at < boundKey(kind, dateBounds(field, to, clock).end)
    );
  }

  // SAFETY: checkFilterQuery accepted one date value for this operator.
  const bounds = dateBounds(field, operand as FilterDateValue, clock);
  const start = boundKey(kind, bounds.start);
  const end = boundKey(kind, bounds.end);

  switch (operator) {
    case "is": {
      return at >= start && at < end;
    }

    case "is_before": {
      return at < start;
    }

    case "is_after": {
      return at >= end;
    }

    case "is_on_or_before": {
      return at < end;
    }

    case "is_on_or_after": {
      return at >= start;
    }

    default: {
      throw new TypeError(`Unknown date operator "${operator}"`);
    }
  }
}

function equalTo(
  field: FilterRecordField,
  operand: unknown,
  value: unknown,
): Truth {
  if (missing(value)) {
    return null;
  }

  switch (field.type) {
    case "boolean": {
      const actual = booleanOf(value);

      return actual === null
        ? null
        : actual === (operand === true || operand === "true");
    }

    case "number": {
      const actual = numberOf(value);

      return actual === null ? null : actual === numberOf(operand);
    }

    case "text":
    case "select":
    case "relation":
    case "multiselect":
    case "date": {
      const actual = textOf(value);

      return actual === null ? null : actual === textOf(operand);
    }

    default: {
      const never: never = field.type;

      throw new TypeError(`Unknown field type ${String(never)}`);
    }
  }
}

function compare(
  operator: "gt" | "gte" | "lt" | "lte",
  operand: unknown,
  value: unknown,
): Truth {
  const actual = numberOf(value);
  const bound = numberOf(operand);

  if (actual === null || bound === null) {
    return null;
  }

  switch (operator) {
    case "gt": {
      return actual > bound;
    }

    case "gte": {
      return actual >= bound;
    }

    case "lt": {
      return actual < bound;
    }

    case "lte": {
      return actual <= bound;
    }

    default: {
      const never: never = operator;

      throw new TypeError(`Unknown operator ${String(never)}`);
    }
  }
}

function listOf(value: unknown): readonly string[] | null {
  if (typeof value === "string" && value.startsWith("[")) {
    try {
      const parsed: unknown = JSON.parse(value);

      return Array.isArray(parsed) ? parsed.map(String) : null;
    } catch {
      return null;
    }
  }

  return Array.isArray(value) ? value.map(String) : null;
}

/** The truth of an operator before negation, mirroring `filterWhere`'s predicates. */
function positive(
  field: FilterRecordField,
  operator: string,
  operand: unknown,
  value: unknown,
  clock: FilterClock,
): Truth {
  switch (operator) {
    case "empty": {
      return field.type === "text"
        ? missing(value) || value === ""
        : missing(value);
    }

    case "contains":
    case "starts_with":
    case "ends_with": {
      const actual = textOf(value);

      if (actual === null) {
        return null;
      }

      const haystack = actual.toLowerCase();
      const needle = String(operand).toLowerCase();

      return operator === "contains"
        ? haystack.includes(needle)
        : operator === "starts_with"
          ? haystack.startsWith(needle)
          : haystack.endsWith(needle);
    }

    case "eq": {
      return equalTo(field, operand, value);
    }

    case "gt":
    case "gte":
    case "lt":
    case "lte": {
      return compare(operator, operand, value);
    }

    case "is_any_of": {
      if (missing(value)) {
        return null;
      }

      const actual = textOf(value);

      return (
        actual !== null &&
        Array.isArray(operand) &&
        operand.some((entry) => textOf(entry) === actual)
      );
    }

    case "has_any_of":
    case "has_all_of": {
      const actual = listOf(value);

      if (actual === null || !Array.isArray(operand)) {
        return null;
      }

      const wanted = operand.map(String);

      return operator === "has_any_of"
        ? wanted.some((entry) => actual.includes(entry))
        : wanted.every((entry) => actual.includes(entry));
    }

    case "is": {
      return field.type === "date"
        ? dateTruth(field, operator, operand, value, clock)
        : equalTo(field, operand, value);
    }

    case "between": {
      if (field.type === "date") {
        return dateTruth(field, operator, operand, value, clock);
      }

      // SAFETY: checkFilterQuery accepted a range of two numbers.
      const [from, to] = operand as readonly [number, number];
      const low = compare("gte", Math.min(from, to), value);
      const high = compare("lte", Math.max(from, to), value);

      return low === null || high === null ? null : low && high;
    }

    default: {
      return dateTruth(field, operator, operand, value, clock);
    }
  }
}

const not = (truth: Truth): Truth => (truth === null ? null : !truth);

function ruleTruth(
  field: FilterRecordField,
  rule: FilterRule,
  record: unknown,
  clock: FilterClock,
): Truth {
  const value = read(record, field.column);
  const base = NEGATIVE[rule.operator];
  const operator = base ?? rule.operator;
  const negative = (base !== undefined) !== (rule.negated === true);
  const truth = positive(field, operator, rule.value, value, clock);

  if (!negative) {
    return truth;
  }

  // "is not x" also matches records without a value, except for "is not empty".
  if (field.columnMeta.nullable && operator !== "empty" && missing(value)) {
    return true;
  }

  return not(truth);
}

function combine(combinator: "and" | "or", parts: readonly Truth[]): Truth {
  if (combinator === "and") {
    return parts.includes(false) ? false : parts.includes(null) ? null : true;
  }

  return parts.includes(true) ? true : parts.includes(null) ? null : false;
}

/**
 * Tests a checked filter tree on one record, with the same operators and
 * null handling as `filterWhere` compiles to SQL. Unfinished rules, unknown
 * fields and empty groups take no part, and a tree with nothing left matches.
 */
export function evaluateFilterQuery(
  query: FilterQuery,
  record: unknown,
  fields: readonly FilterRecordField[],
  clock: FilterClock = {},
): FilterEvaluation {
  const byId = new Map(fields.map((field) => [field.id, field]));
  const results: Record<string, Truth> = {};

  const visit = (node: FilterNode): Truth | undefined => {
    if (node.type === "rule") {
      const field = byId.get(node.path.join("."));

      if (node.operator === "" || !field) {
        return undefined;
      }

      const truth = ruleTruth(field, node, record, clock);
      results[node.id] = truth;

      return truth;
    }

    const parts = node.rules.flatMap((child) => {
      const truth = visit(child);

      return truth === undefined ? [] : [truth];
    });

    if (parts.length === 0) {
      return undefined;
    }

    const truth = combine(node.combinator, parts);
    results[node.id] = truth;

    return truth;
  };

  const root = visit(query);

  return { matched: root === undefined || root === true, results };
}
