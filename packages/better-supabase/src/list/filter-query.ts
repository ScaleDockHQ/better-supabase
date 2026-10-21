/// <reference lib="esnext.temporal" />

import type { ValidationIssue } from "../core/errors.ts";
import type { ColumnMeta, TableMeta } from "../schema/types.ts";

import { isRecord } from "../core/guards.ts";
import { optionalTemporal, TEMPORAL_MISSING } from "../core/temporal.ts";
import { escapeLike } from "../ir/escape-like.ts";

/*
 * The filter tree ReUI's Filters component edits, typed structurally: no
 * import from ReUI. `FilterQuery` is the root group; a rule whose `operator`
 * is `""` is unfinished and matches everything, as `flattenFilterConditions`
 * leaves it out.
 */

export type FilterCombinator = "and" | "or";

export interface FilterRule<V = unknown> {
  readonly id: string;
  readonly type: "rule";
  readonly path: readonly string[];
  readonly operator: string;
  readonly value?: V | undefined;
  readonly negated?: boolean;
}

export interface FilterGroupNode<V = unknown> {
  readonly id: string;
  readonly type: "group";
  readonly combinator: FilterCombinator;
  readonly rules: readonly FilterNode<V>[];
}

export type FilterNode<V = unknown> = FilterRule<V> | FilterGroupNode<V>;

export type FilterQuery<V = unknown> = FilterGroupNode<V>;

/** A calendar offset from today, resolved when the query runs. */
export interface FilterRelativeDate {
  readonly unit: "day" | "week" | "month" | "year";
  readonly offset: number;
}

/** A date value: an absolute `yyyy-MM-dd` day or a relative token, with an optional `HH:mm`. */
export interface FilterDateValue {
  readonly date?: string;
  readonly relative?: FilterRelativeDate;
  readonly time?: string;
}

export type FilterOperatorArity = "none" | "one" | "many" | "range";

/** The value types a list filter field takes. `date` and `relation` map onto ReUI editors. */
export type FilterFieldType =
  | "text"
  | "number"
  | "date"
  | "select"
  | "multiselect"
  | "boolean"
  | "relation";

export interface FilterOperatorSpec {
  readonly value: string;
  readonly arity: FilterOperatorArity;
  readonly inverse?: string;
}

const op = (
  value: string,
  arity: FilterOperatorArity = "one",
  inverse?: string,
): FilterOperatorSpec => ({
  value,
  arity,
  ...(inverse === undefined ? {} : { inverse }),
});

const EMPTY = [
  op("empty", "none", "not_empty"),
  op("not_empty", "none", "empty"),
];

const SELECT = [
  op("is", "one", "is_not"),
  op("is_not", "one", "is"),
  op("is_any_of", "many", "is_none_of"),
  op("is_none_of", "many", "is_any_of"),
  ...EMPTY,
];

/** The operators each field type allows, in the order ReUI lists them. */
export const FILTER_OPERATORS: Readonly<
  Record<FilterFieldType, readonly FilterOperatorSpec[]>
> = {
  text: [
    op("contains", "one", "not_contains"),
    op("not_contains", "one", "contains"),
    op("starts_with"),
    op("ends_with"),
    op("is", "one", "is_not"),
    op("is_not", "one", "is"),
    ...EMPTY,
  ],
  number: [
    op("eq", "one", "neq"),
    op("neq", "one", "eq"),
    op("gt", "one", "lte"),
    op("gte", "one", "lt"),
    op("lt", "one", "gte"),
    op("lte", "one", "gt"),
    op("between", "range", "not_between"),
    op("not_between", "range", "between"),
    ...EMPTY,
  ],
  date: [
    op("is", "one", "is_not"),
    op("is_not", "one", "is"),
    op("is_before", "one", "is_on_or_after"),
    op("is_after", "one", "is_on_or_before"),
    op("is_on_or_before", "one", "is_after"),
    op("is_on_or_after", "one", "is_before"),
    op("between", "range", "not_between"),
    op("not_between", "range", "between"),
    ...EMPTY,
  ],
  select: SELECT,
  relation: SELECT,
  multiselect: [
    op("has_any_of", "many", "has_none_of"),
    op("has_all_of", "many"),
    op("has_none_of", "many", "has_any_of"),
    ...EMPTY,
  ],
  boolean: [op("is", "one", "is_not"), op("is_not", "one", "is"), ...EMPTY],
};

/** English operator labels, the defaults `filterFields` uses. */
export const FILTER_OPERATOR_LABELS: Readonly<Record<string, string>> = {
  contains: "contains",
  not_contains: "does not contain",
  starts_with: "starts with",
  ends_with: "ends with",
  is: "is",
  is_not: "is not",
  is_any_of: "is any of",
  is_none_of: "is none of",
  has_any_of: "has any of",
  has_all_of: "has all of",
  has_none_of: "has none of",
  eq: "equals",
  neq: "does not equal",
  gt: "is greater than",
  gte: "is greater than or equal to",
  lt: "is less than",
  lte: "is less than or equal to",
  between: "is between",
  not_between: "is not between",
  is_before: "is before",
  is_after: "is after",
  is_on_or_before: "is on or before",
  is_on_or_after: "is on or after",
  empty: "is empty",
  not_empty: "is not empty",
};

/** One entry of `defineListQuery`'s `filters`: a field the tree may name. */
export interface ListFilterConfig<C extends string = string> {
  readonly type: FilterFieldType;
  /** The column the field filters; defaults to the field id. */
  readonly column?: C;
  readonly label?: string;
  readonly description?: string;
  /** A subset of the type's operators. */
  readonly operators?: readonly string[];
  readonly defaultOperator?: string;
  /** Allowed values for `select` and `multiselect`; defaults to the column's enum. */
  readonly options?: readonly (
    | string
    | { readonly value: string; readonly label?: string }
  )[];
}

/** A checked filter field. */
export interface FilterFieldInfo {
  readonly id: string;
  readonly type: FilterFieldType;
  /** Model key of the column. */
  readonly column: string;
  readonly columnMeta: ColumnMeta;
  readonly label: string;
  readonly description?: string;
  readonly operators: readonly FilterOperatorSpec[];
  readonly defaultOperator?: string;
  readonly options?: readonly {
    readonly value: string;
    readonly label: string;
  }[];
}

const DATE_TYPES = new Set(["date", "timestamp", "timestamptz"]);

const NUMBER_TYPES = new Set([
  "int2",
  "int4",
  "int8",
  "float4",
  "float8",
  "numeric",
  "money",
]);

function labelOf(id: string): string {
  const words = id
    .replaceAll(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replaceAll(/[_.-]+/g, " ")
    .trim()
    .toLowerCase();

  return words.charAt(0).toUpperCase() + words.slice(1);
}

/** Checks the `filters` config of a list against the table. */
export function filterFieldsOf(
  table: TableMeta,
  filters: Readonly<Record<string, ListFilterConfig>>,
): readonly FilterFieldInfo[] {
  return Object.entries(filters).map(([id, config]) => {
    const where = `defineListQuery: filter "${id}"`;
    const column = config.column ?? id;
    const columnMeta = table.columns[column];

    if (!columnMeta) {
      throw new TypeError(`${where}: unknown column "${table.key}.${column}"`);
    }

    const catalog = FILTER_OPERATORS[config.type];

    // oxlint-disable-next-line typescript/no-unnecessary-condition -- configs from JavaScript can name any type.
    if (catalog === undefined) {
      throw new TypeError(
        `${where}: type must be one of ${Object.keys(FILTER_OPERATORS).join(", ")}`,
      );
    }

    if (config.type === "multiselect" && columnMeta.array !== true) {
      throw new TypeError(
        `${where}: multiselect needs an array column; use select for "${column}"`,
      );
    }

    if (config.type === "date" && !DATE_TYPES.has(columnMeta.type)) {
      throw new TypeError(
        `${where}: date needs a date, timestamp or timestamptz column`,
      );
    }

    if (config.type === "number" && !NUMBER_TYPES.has(columnMeta.type)) {
      throw new TypeError(`${where}: number needs a numeric column`);
    }

    if (config.type === "boolean" && columnMeta.type !== "bool") {
      throw new TypeError(`${where}: boolean needs a bool column`);
    }

    const operators =
      config.operators === undefined
        ? catalog
        : config.operators.map((name) => {
            const found = catalog.find((entry) => entry.value === name);

            if (!found) {
              throw new TypeError(
                `${where}: operator "${name}" is not a ${config.type} operator. Operators: ${catalog.map((entry) => entry.value).join(", ")}`,
              );
            }

            return found;
          });

    if (
      config.defaultOperator !== undefined &&
      !operators.some((entry) => entry.value === config.defaultOperator)
    ) {
      throw new TypeError(
        `${where}: defaultOperator "${config.defaultOperator}" is not one of its operators`,
      );
    }

    const options =
      config.options?.map((option) =>
        typeof option === "string"
          ? { value: option, label: option }
          : { value: option.value, label: option.label ?? option.value },
      ) ??
      (config.type === "select" || config.type === "multiselect"
        ? columnMeta.enum?.map((value) => ({ value, label: value }))
        : undefined);

    return {
      id,
      type: config.type,
      column,
      columnMeta,
      label: config.label ?? labelOf(id),
      ...(config.description === undefined
        ? {}
        : { description: config.description }),
      operators,
      ...(config.defaultOperator === undefined
        ? {}
        : { defaultOperator: config.defaultOperator }),
      ...(options === undefined ? {} : { options }),
    };
  });
}

export interface FilterLimits {
  readonly maxDepth: number;
  readonly maxRules: number;
  readonly maxValueLength: number;
  readonly maxValues: number;
}

const DATE = /^\d{4}-\d{2}-\d{2}$/;
const TIME = /^(?:[01]\d|2[0-3]):[0-5]\d$/;
const UNITS = new Set(["day", "week", "month", "year"]);

function validDay(date: string): boolean {
  if (!DATE.test(date)) {
    return false;
  }

  const [year = 0, month = 0, day = 0] = date.split("-").map(Number);
  const probe = new Date(Date.UTC(year, month - 1, day));

  return (
    probe.getUTCFullYear() === year &&
    probe.getUTCMonth() === month - 1 &&
    probe.getUTCDate() === day
  );
}

function dateValueIssue(value: unknown): string | undefined {
  if (!isRecord(value)) {
    return "Must be a date value";
  }

  const { date, relative, time } = value;

  if ((date === undefined) === (relative === undefined)) {
    return "Give either date or relative";
  }

  if (date !== undefined && (typeof date !== "string" || !validDay(date))) {
    return "date must be a yyyy-MM-dd day";
  }

  if (
    relative !== undefined &&
    (!isRecord(relative) ||
      typeof relative["unit"] !== "string" ||
      !UNITS.has(relative["unit"]) ||
      !Number.isSafeInteger(relative["offset"]) ||
      Math.abs(Number(relative["offset"])) > 100_000)
  ) {
    return "relative must be { unit: day | week | month | year, offset: whole number }";
  }

  if (time !== undefined && (typeof time !== "string" || !TIME.test(time))) {
    return "time must be HH:mm";
  }

  return undefined;
}

function scalarIssue(
  field: FilterFieldInfo,
  value: unknown,
  limits: FilterLimits,
): string | undefined {
  switch (field.type) {
    case "text": {
      if (typeof value !== "string") {
        return "Must be text";
      }

      if (value.length > limits.maxValueLength) {
        return `At most ${String(limits.maxValueLength)} characters`;
      }

      return undefined;
    }

    case "number": {
      return typeof value === "number" && Number.isFinite(value)
        ? undefined
        : "Must be a number";
    }

    case "boolean": {
      return typeof value === "boolean" || value === "true" || value === "false"
        ? undefined
        : "Must be true or false";
    }

    case "date": {
      return dateValueIssue(value);
    }

    case "select":
    case "multiselect":
    case "relation": {
      if (typeof value !== "string" || value === "") {
        return "Must be a value";
      }

      if (value.length > limits.maxValueLength) {
        return `At most ${String(limits.maxValueLength)} characters`;
      }

      if (
        field.options !== undefined &&
        !field.options.some((option) => option.value === value)
      ) {
        return `Must be one of: ${field.options.map((option) => option.value).join(", ")}`;
      }

      return undefined;
    }

    default: {
      const never: never = field.type;

      return `Unknown field type ${String(never)}`;
    }
  }
}

function valueIssue(
  field: FilterFieldInfo,
  arity: FilterOperatorArity,
  value: unknown,
  limits: FilterLimits,
): string | undefined {
  switch (arity) {
    case "none": {
      return undefined;
    }

    case "one": {
      if (value === undefined || value === null) {
        return "Needs a value";
      }

      return scalarIssue(field, value, limits);
    }

    case "many": {
      if (!Array.isArray(value) || value.length === 0) {
        return "Needs a list of values";
      }

      if (value.length > limits.maxValues) {
        return `At most ${String(limits.maxValues)} values`;
      }

      for (const entry of value) {
        const issue = scalarIssue(field, entry, limits);

        if (issue) {
          return issue;
        }
      }

      return undefined;
    }

    case "range": {
      if (!Array.isArray(value) || value.length !== 2) {
        return "Needs two values, from and to";
      }

      for (const entry of value) {
        const issue = scalarIssue(field, entry, limits);

        if (issue) {
          return issue;
        }
      }

      return undefined;
    }

    default: {
      const never: never = arity;

      return `Unknown arity ${String(never)}`;
    }
  }
}

/**
 * Checks a filter tree against the fields and returns it without unfinished
 * rules and empty groups. `undefined` when nothing is left.
 */
export function checkFilterQuery(
  input: unknown,
  fields: readonly FilterFieldInfo[],
  limits: FilterLimits,
  issues: ValidationIssue[],
): FilterQuery | undefined {
  const byId = new Map(fields.map((field) => [field.id, field]));
  let rules = 0;

  const visit = (
    node: unknown,
    path: readonly PropertyKey[],
    depth: number,
  ): FilterNode | null => {
    const fail = (message: string, at: readonly PropertyKey[] = path): null => {
      issues.push({ message, path: at });

      return null;
    };

    if (!isRecord(node)) {
      return fail("Must be a filter group or rule");
    }

    if (typeof node["id"] !== "string") {
      return fail("Needs an id");
    }

    if (node["type"] === "group") {
      if (depth > limits.maxDepth) {
        return fail(`At most ${String(limits.maxDepth)} levels of groups`);
      }

      const combinator = node["combinator"];

      if (combinator !== "and" && combinator !== "or") {
        return fail('combinator must be "and" or "or"', [
          ...path,
          "combinator",
        ]);
      }

      const children = node["rules"];

      if (!Array.isArray(children)) {
        return fail("rules must be a list", [...path, "rules"]);
      }

      const kept = children.flatMap((child: unknown, index) => {
        const next = visit(child, [...path, "rules", index], depth + 1);

        return next === null ? [] : [next];
      });

      if (kept.length === 0) {
        return null;
      }

      return { id: node["id"], type: "group", combinator, rules: kept };
    }

    if (node["type"] !== "rule") {
      return fail('type must be "group" or "rule"');
    }

    rules += 1;

    if (rules > limits.maxRules) {
      return rules === limits.maxRules + 1
        ? fail(`At most ${String(limits.maxRules)} rules`)
        : null;
    }

    const rulePath = node["path"];

    if (
      !Array.isArray(rulePath) ||
      rulePath.length === 0 ||
      !rulePath.every((segment) => typeof segment === "string")
    ) {
      return fail("path must be a list of field ids", [...path, "path"]);
    }

    const id = rulePath.join(".");
    const field = byId.get(id);

    if (!field) {
      return fail(
        `Unknown filter field "${id}". Fields: ${[...byId.keys()].join(", ")}`,
        [...path, "path"],
      );
    }

    const operator = node["operator"];

    if (typeof operator !== "string") {
      return fail("operator must be text", [...path, "operator"]);
    }

    if (operator === "") {
      return null;
    }

    const spec = field.operators.find((entry) => entry.value === operator);

    if (!spec) {
      return fail(
        `"${operator}" is not an operator of ${field.id}. Operators: ${field.operators.map((entry) => entry.value).join(", ")}`,
        [...path, "operator"],
      );
    }

    const negated = node["negated"];

    if (negated !== undefined && typeof negated !== "boolean") {
      return fail("negated must be true or false", [...path, "negated"]);
    }

    const value = node["value"];
    const issue = valueIssue(field, spec.arity, value, limits);

    if (issue) {
      return fail(issue, [...path, "value"]);
    }

    return {
      id: node["id"],
      type: "rule",
      path: rulePath,
      operator,
      ...(spec.arity === "none" ? {} : { value }),
      ...(negated === true ? { negated } : {}),
    };
  };

  const root = visit(input, ["filter"], 1);

  if (root?.type === "rule") {
    issues.push({ message: "The root must be a group", path: ["filter"] });

    return undefined;
  }

  return root ?? undefined;
}

type Where = Record<string, unknown>;

export interface FilterClock {
  /** IANA time zone dates resolve in. Defaults to `UTC`. */
  readonly timeZone?: string;
  /** The current instant; defaults to `Temporal.Now`. */
  readonly now?: Temporal.Instant;
}

/** Resolves date values to bounds in the column's own representation. */
export function dateBounds(
  field: { readonly columnMeta: { readonly type: string } },
  value: FilterDateValue,
  clock: FilterClock,
): { readonly start: string; readonly end: string } {
  const T = optionalTemporal();

  if (T === undefined) {
    throw new TypeError(TEMPORAL_MISSING);
  }

  const zone = clock.timeZone ?? "UTC";
  const now = clock.now ?? T.Now.instant();
  let day: Temporal.PlainDate;

  if (value.relative) {
    const today = now.toZonedDateTimeISO(zone).toPlainDate();
    const { unit, offset } = value.relative;
    day = today.add(
      unit === "day"
        ? { days: offset }
        : unit === "week"
          ? { weeks: offset }
          : unit === "month"
            ? { months: offset }
            : { years: offset },
    );
  } else {
    day = T.PlainDate.from(value.date ?? "");
  }

  const kind = field.columnMeta.type;

  if (kind === "date") {
    return { start: day.toString(), end: day.add({ days: 1 }).toString() };
  }

  const time = value.time ? T.PlainTime.from(value.time) : undefined;
  const from = day.toPlainDateTime(time);
  const to = time ? from.add({ minutes: 1 }) : from.add({ days: 1 });

  if (kind === "timestamp") {
    return { start: from.toString(), end: to.toString() };
  }

  return {
    start: from.toZonedDateTime(zone).toInstant().toString(),
    end: to.toZonedDateTime(zone).toInstant().toString(),
  };
}

function dateWhere(
  field: FilterFieldInfo,
  operator: string,
  value: unknown,
  clock: FilterClock,
): Where {
  const column = field.column;

  if (operator === "between") {
    // SAFETY: checkFilterQuery accepted a range of two date values.
    const [from, to] = value as readonly [FilterDateValue, FilterDateValue];

    return {
      [column]: {
        gte: dateBounds(field, from, clock).start,
        lt: dateBounds(field, to, clock).end,
      },
    };
  }

  // SAFETY: checkFilterQuery accepted one date value for this operator.
  const { start, end } = dateBounds(field, value as FilterDateValue, clock);

  switch (operator) {
    case "is": {
      return { [column]: { gte: start, lt: end } };
    }

    case "is_before": {
      return { [column]: { lt: start } };
    }

    case "is_after": {
      return { [column]: { gte: end } };
    }

    case "is_on_or_before": {
      return { [column]: { lt: end } };
    }

    case "is_on_or_after": {
      return { [column]: { gte: start } };
    }

    default: {
      throw new TypeError(`Unknown date operator "${operator}"`);
    }
  }
}

/** The predicate of an operator, before negation. */
function positive(
  field: FilterFieldInfo,
  operator: string,
  value: unknown,
  clock: FilterClock,
): Where {
  const column = field.column;

  switch (operator) {
    case "empty": {
      return field.type === "text"
        ? { OR: [{ [column]: { isNull: true } }, { [column]: { eq: "" } }] }
        : { [column]: { isNull: true } };
    }

    case "contains": {
      return { [column]: { contains: value } };
    }

    // Case-insensitive, like `contains`.
    case "starts_with": {
      return { [column]: { ilike: `${escapeLike(String(value))}%` } };
    }

    case "ends_with": {
      return { [column]: { ilike: `%${escapeLike(String(value))}` } };
    }

    case "eq": {
      return { [column]: { eq: value } };
    }

    case "gt":
    case "gte":
    case "lt":
    case "lte": {
      return { [column]: { [operator]: value } };
    }

    case "is_any_of": {
      return { [column]: { in: value } };
    }

    case "has_any_of": {
      return { [column]: { hasSome: value } };
    }

    case "has_all_of": {
      return { [column]: { hasEvery: value } };
    }

    case "is": {
      if (field.type === "date") {
        return dateWhere(field, operator, value, clock);
      }

      return {
        [column]: {
          eq:
            field.type === "boolean"
              ? value === true || value === "true"
              : value,
        },
      };
    }

    case "between": {
      if (field.type === "date") {
        return dateWhere(field, operator, value, clock);
      }

      // SAFETY: checkFilterQuery accepted a range of two numbers.
      const [from, to] = value as readonly [number, number];

      return { [column]: { gte: Math.min(from, to), lte: Math.max(from, to) } };
    }

    default: {
      return dateWhere(field, operator, value, clock);
    }
  }
}

/** Negative operators and the positive operator they negate. */
export const NEGATIVE: Readonly<Record<string, string>> = {
  not_empty: "empty",
  not_contains: "contains",
  is_not: "is",
  neq: "eq",
  not_between: "between",
  is_none_of: "is_any_of",
  has_none_of: "has_any_of",
};

function ruleWhere(
  field: FilterFieldInfo,
  rule: FilterRule,
  clock: FilterClock,
): Where {
  const base = NEGATIVE[rule.operator];
  const negative = (base !== undefined) !== (rule.negated === true);
  const predicate = positive(field, base ?? rule.operator, rule.value, clock);

  if (!negative) {
    return predicate;
  }

  // "is not x" also matches rows without a value, except for "is not empty".
  const emptiness = (base ?? rule.operator) === "empty";

  return field.columnMeta.nullable && !emptiness
    ? { OR: [{ NOT: predicate }, { [field.column]: { isNull: true } }] }
    : { NOT: predicate };
}

/** A checked filter tree as a repository `where`. */
export function filterWhere(
  query: FilterQuery,
  fields: readonly FilterFieldInfo[],
  clock: FilterClock = {},
): Where | undefined {
  const byId = new Map(fields.map((field) => [field.id, field]));

  const visit = (node: FilterNode): Where | undefined => {
    if (node.type === "rule") {
      if (node.operator === "") {
        return undefined;
      }

      const field = byId.get(node.path.join("."));

      return field ? ruleWhere(field, node, clock) : undefined;
    }

    const parts = node.rules.flatMap((child) => {
      const next = visit(child);

      return next === undefined ? [] : [next];
    });

    if (parts.length === 0) {
      return undefined;
    }

    if (parts.length === 1) {
      return parts[0];
    }

    return node.combinator === "and" ? { AND: parts } : { OR: parts };
  };

  return visit(query);
}

/** The structural `FilterField` objects ReUI Filters takes. */
export interface FilterField {
  readonly id: string;
  readonly label: string;
  readonly description?: string;
  readonly type?: "text" | "number" | "select" | "multiselect" | "boolean";
  readonly options?: readonly {
    readonly value: string;
    readonly label: string;
  }[];
  readonly operators?: readonly {
    readonly value: string;
    readonly label: string;
    readonly arity: FilterOperatorArity;
    readonly inverse?: string;
  }[];
  readonly defaultOperator?: string;
  /** The column the field filters. */
  readonly column: string;
}

export interface FilterFieldLabels {
  /** Field labels by field id. */
  readonly fields?: Readonly<Record<string, string>>;
  /** Operator labels by operator value. */
  readonly operators?: Readonly<Record<string, string>>;
  /** Option labels by field id, then by option value. */
  readonly options?: Readonly<Record<string, Readonly<Record<string, string>>>>;
}

/** ReUI value types for each field type; `date` uses an editor, `relation` a select. */
const REUI_TYPE = {
  text: "text",
  number: "number",
  date: undefined,
  select: "select",
  multiselect: "multiselect",
  boolean: "boolean",
  relation: "select",
} as const satisfies Record<FilterFieldType, FilterField["type"]>;

export function toFilterFields(
  fields: readonly FilterFieldInfo[],
  labels: FilterFieldLabels = {},
): FilterField[] {
  return fields.map((field) => {
    const type = REUI_TYPE[field.type];
    const catalog = FILTER_OPERATORS[field.type];

    const custom =
      field.type === "date" ||
      field.operators.length !== catalog.length ||
      labels.operators !== undefined;

    const allowed = new Set(field.operators.map((entry) => entry.value));
    const optionLabels = labels.options?.[field.id];

    return {
      id: field.id,
      label: labels.fields?.[field.id] ?? field.label,
      ...(field.description === undefined
        ? {}
        : { description: field.description }),
      ...(type === undefined ? {} : { type }),
      ...(field.options === undefined
        ? {}
        : {
            options: field.options.map((option) => ({
              value: option.value,
              label: optionLabels?.[option.value] ?? option.label,
            })),
          }),
      ...(custom
        ? {
            operators: field.operators.map((entry) => ({
              value: entry.value,
              label:
                labels.operators?.[entry.value] ??
                FILTER_OPERATOR_LABELS[entry.value] ??
                entry.value,
              arity: entry.arity,
              ...(entry.inverse !== undefined && allowed.has(entry.inverse)
                ? { inverse: entry.inverse }
                : {}),
            })),
          }
        : {}),
      ...(field.defaultOperator === undefined
        ? {}
        : { defaultOperator: field.defaultOperator }),
      column: field.columnMeta.db,
    };
  });
}

/** `base64url` of the tree's JSON, for one URL parameter. */
export function encodeFilterQuery(query: FilterQuery): string {
  const bytes = new TextEncoder().encode(JSON.stringify(query));
  let binary = "";

  for (const byte of bytes) {
    binary += String.fromCodePoint(byte);
  }

  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/[=]+$/, "");
}

/** The JSON a `filter` URL parameter holds, or `undefined` when it is not base64url JSON. */
export function decodeFilterQuery(encoded: string): unknown {
  if (!/^[A-Za-z0-9_-]*$/.test(encoded)) {
    return undefined;
  }

  try {
    const binary = atob(encoded.replaceAll("-", "+").replaceAll("_", "/"));
    const bytes = Uint8Array.from(binary, (char) => char.codePointAt(0) ?? 0);

    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    return undefined;
  }
}

/** JSON Schema of a filter tree over the given fields, with `$defs`. */
export function filterJsonSchema(
  fields: readonly FilterFieldInfo[],
  limits: FilterLimits,
): Readonly<Record<string, unknown>> {
  const operators = [
    ...new Set(fields.flatMap((field) => field.operators.map((o) => o.value))),
  ];

  return {
    $defs: {
      filterGroup: {
        type: "object",
        required: ["id", "type", "combinator", "rules"],
        properties: {
          id: { type: "string" },
          type: { const: "group" },
          combinator: { enum: ["and", "or"] },
          rules: {
            type: "array",
            maxItems: limits.maxRules,
            items: {
              oneOf: [
                { $ref: "#/$defs/filterGroup" },
                { $ref: "#/$defs/filterRule" },
              ],
            },
          },
        },
      },
      filterRule: {
        type: "object",
        required: ["id", "type", "path", "operator"],
        properties: {
          id: { type: "string" },
          type: { const: "rule" },
          path: {
            type: "array",
            minItems: 1,
            items: { type: "string" },
            description: `The field id, split on dots. Fields: ${fields.map((field) => `${field.id} (${field.type})`).join(", ")}.`,
          },
          operator: { enum: ["", ...operators] },
          value: {
            description:
              "The operand: one value, a list for any-of operators, or [from, to] for between. Dates are { date: 'yyyy-MM-dd' } or { relative: { unit, offset } }, with an optional time 'HH:mm'.",
          },
          negated: { type: "boolean" },
        },
      },
    },
  };
}
