/** SCIM filters (RFC 7644 §3.4.2.2): parsing and evaluation over resource JSON. */

import { isRecord } from "../shared.ts";

export type CompareOp =
  | "eq"
  | "ne"
  | "co"
  | "sw"
  | "ew"
  | "gt"
  | "ge"
  | "lt"
  | "le";

export type ScimFilter =
  | {
      readonly op: "and" | "or";
      readonly left: ScimFilter;
      readonly right: ScimFilter;
    }
  | { readonly op: "not"; readonly filter: ScimFilter }
  | { readonly op: "pr"; readonly path: string }
  | {
      readonly op: CompareOp;
      readonly path: string;
      readonly value: string | number | boolean | null;
    }
  | {
      readonly op: "value";
      readonly path: string;
      readonly filter: ScimFilter;
    };

/** A filter the service provider can't parse or apply: 400 `invalidFilter`. */
export class ScimFilterError extends Error {
  override readonly name = "ScimFilterError";
}

const COMPARE: readonly CompareOp[] = [
  "eq",
  "ne",
  "co",
  "sw",
  "ew",
  "gt",
  "ge",
  "lt",
  "le",
];

type Token =
  | { readonly kind: "punct"; readonly value: "(" | ")" | "[" | "]" }
  | { readonly kind: "string"; readonly value: string }
  | { readonly kind: "word"; readonly value: string };

function tokenize(input: string): Token[] {
  const tokens: Token[] = [];
  let i = 0;
  while (i < input.length) {
    const char = input.charAt(i);
    if (/\s/.test(char)) {
      i += 1;
    } else if (char === "(" || char === ")" || char === "[" || char === "]") {
      tokens.push({ kind: "punct", value: char });
      i += 1;
    } else if (char === '"') {
      let end = i + 1;
      while (end < input.length && input.charAt(end) !== '"') {
        end += input.charAt(end) === "\\" ? 2 : 1;
      }
      if (end >= input.length) throw new ScimFilterError("Unterminated string");
      const raw = input.slice(i, end + 1);
      let value: unknown;
      try {
        value = JSON.parse(raw);
      } catch {
        throw new ScimFilterError(`Invalid string ${raw}`);
      }
      tokens.push({ kind: "string", value: String(value) });
      i = end + 1;
    } else {
      let end = i;
      while (end < input.length && !/[\s()[\]"]/.test(input.charAt(end))) {
        end += 1;
      }
      tokens.push({ kind: "word", value: input.slice(i, end) });
      i = end;
    }
  }
  return tokens;
}

const ATTR_PATH = /^(?:urn:[^\s]+:)?[A-Za-z$][\w$-]*(?:\.[A-Za-z$][\w$-]*)?$/;

/** Parses a SCIM filter; throws `ScimFilterError`. */
export function parseFilter(input: string): ScimFilter {
  const tokens = tokenize(input);
  let position = 0;
  const peek = (): Token | undefined => tokens[position];
  const keyword = (word: string): boolean => {
    const token = peek();
    return (
      token?.kind === "word" && token.value.toLowerCase() === word.toLowerCase()
    );
  };
  const expect = (value: ")" | "]"): void => {
    const token = peek();
    if (token?.kind !== "punct" || token.value !== value) {
      throw new ScimFilterError(`Expected ${value}`);
    }
    position += 1;
  };

  const orExpression = (): ScimFilter => {
    let left = andExpression();
    while (keyword("or")) {
      position += 1;
      left = { op: "or", left, right: andExpression() };
    }
    return left;
  };
  const andExpression = (): ScimFilter => {
    let left = notExpression();
    while (keyword("and")) {
      position += 1;
      left = { op: "and", left, right: notExpression() };
    }
    return left;
  };
  const notExpression = (): ScimFilter => {
    if (keyword("not")) {
      position += 1;
      const open = peek();
      if (open?.kind !== "punct" || open.value !== "(") {
        throw new ScimFilterError("Expected ( after not");
      }
      position += 1;
      const filter = orExpression();
      expect(")");
      return { op: "not", filter };
    }
    return atom();
  };
  const atom = (): ScimFilter => {
    const token = peek();
    if (token?.kind === "punct" && token.value === "(") {
      position += 1;
      const filter = orExpression();
      expect(")");
      return filter;
    }
    if (token?.kind !== "word" || !ATTR_PATH.test(token.value)) {
      throw new ScimFilterError("Expected an attribute path");
    }
    position += 1;
    const path = token.value;
    const next = peek();
    if (next?.kind === "punct" && next.value === "[") {
      position += 1;
      const filter = orExpression();
      expect("]");
      return { op: "value", path, filter };
    }
    if (next?.kind !== "word") {
      throw new ScimFilterError(`Expected an operator after ${path}`);
    }
    const op = next.value.toLowerCase();
    position += 1;
    if (op === "pr") return { op: "pr", path };
    const compare = COMPARE.find((candidate) => candidate === op);
    if (compare === undefined) {
      throw new ScimFilterError(`Unknown operator ${next.value}`);
    }
    return { op: compare, path, value: literal() };
  };
  const literal = (): string | number | boolean | null => {
    const token = peek();
    position += 1;
    if (token?.kind === "string") return token.value;
    if (token?.kind === "word") {
      const word = token.value.toLowerCase();
      if (word === "true") return true;
      if (word === "false") return false;
      if (word === "null") return null;
      if (/^-?\d+(\.\d+)?([eE][+-]?\d+)?$/.test(token.value)) {
        return Number(token.value);
      }
    }
    throw new ScimFilterError("Expected a value");
  };

  if (tokens.length === 0) throw new ScimFilterError("Empty filter");
  const filter = orExpression();
  if (position !== tokens.length) {
    throw new ScimFilterError("Unexpected input after the filter");
  }
  return filter;
}

/** The attribute paths compared case-sensitively (RFC 7643 `caseExact`). */
const CASE_EXACT = new Set(["id", "externalid", "meta.version"]);
const DATES = new Set(["meta.created", "meta.lastmodified"]);

function lookup(record: Record<string, unknown>, name: string): unknown {
  const lower = name.toLowerCase();
  for (const [key, value] of Object.entries(record)) {
    if (key.toLowerCase() === lower) return value;
  }
  return undefined;
}

/** The URN prefix of `path` when it names one of the resource's schemas, and the rest. */
function relative(
  resource: Record<string, unknown>,
  path: string,
): string | undefined {
  const colon = path.lastIndexOf(":");
  if (colon === -1) return path;
  const urn = path.slice(0, colon).toLowerCase();
  const known = Array.isArray(resource["schemas"])
    ? resource["schemas"].map((schema) => String(schema).toLowerCase())
    : [];
  return known.includes(urn) ? path.slice(colon + 1) : undefined;
}

/** The values at `path`; multi-valued complex attributes give their `value`s. */
function valuesAt(
  resource: Record<string, unknown>,
  path: string,
): readonly unknown[] {
  const local = relative(resource, path);
  if (local === undefined) return [];
  const [attribute = "", sub] = local.split(".");
  const value = lookup(resource, attribute);
  if (value === undefined || value === null) return [];
  if (Array.isArray(value)) {
    const items: readonly unknown[] = value;
    return items
      .map((item) =>
        isRecord(item) ? lookup(item, sub ?? "value") : sub ? undefined : item,
      )
      .filter((item) => item !== undefined && item !== null);
  }
  if (isRecord(value)) {
    if (sub === undefined) return [];
    const inner = lookup(value, sub);
    return inner === undefined || inner === null ? [] : [inner];
  }
  return sub === undefined ? [value] : [];
}

function compare(
  op: CompareOp,
  actual: unknown,
  expected: string | number | boolean | null,
  path: string,
): boolean {
  const key = path.slice(path.lastIndexOf(":") + 1).toLowerCase();
  if (typeof actual === "boolean" || typeof expected === "boolean") {
    if (op !== "eq" && op !== "ne") {
      throw new ScimFilterError(`${op} does not apply to booleans`);
    }
    return op === "eq" ? actual === expected : actual !== expected;
  }
  if (expected === null) return op === "ne" ? actual !== null : actual === null;
  if (typeof actual === "number" && typeof expected === "number") {
    return order(op, actual - expected);
  }
  if (typeof actual !== "string") return op === "ne";
  if (typeof expected !== "string") return op === "ne";
  if (DATES.has(key)) {
    const left = Date.parse(actual);
    const right = Date.parse(expected);
    if (!Number.isNaN(left) && !Number.isNaN(right)) {
      return order(op, left - right);
    }
  }
  const exact = CASE_EXACT.has(key);
  const a = exact ? actual : actual.toLowerCase();
  const b = exact ? expected : expected.toLowerCase();
  switch (op) {
    case "co":
      return a.includes(b);
    case "sw":
      return a.startsWith(b);
    case "ew":
      return a.endsWith(b);
    case "eq":
    case "ne":
    case "gt":
    case "ge":
    case "lt":
    case "le":
      return order(op, a < b ? -1 : a > b ? 1 : 0);
    default: {
      const unreachable: never = op;
      throw new ScimFilterError(`Unknown operator ${String(unreachable)}`);
    }
  }
}

function order(op: CompareOp, difference: number): boolean {
  switch (op) {
    case "eq":
      return difference === 0;
    case "ne":
      return difference !== 0;
    case "gt":
      return difference > 0;
    case "ge":
      return difference >= 0;
    case "lt":
      return difference < 0;
    case "le":
      return difference <= 0;
    case "co":
    case "sw":
    case "ew":
      throw new ScimFilterError(`${op} applies to strings`);
    default: {
      const unreachable: never = op;
      throw new ScimFilterError(`Unknown operator ${String(unreachable)}`);
    }
  }
}

/** Whether `resource` matches; a multi-valued attribute matches when any value does. */
export function matches(
  resource: Record<string, unknown>,
  filter: ScimFilter,
): boolean {
  switch (filter.op) {
    case "and":
      return matches(resource, filter.left) && matches(resource, filter.right);
    case "or":
      return matches(resource, filter.left) || matches(resource, filter.right);
    case "not":
      return !matches(resource, filter.filter);
    case "pr":
      return valuesAt(resource, filter.path).some(
        (value) =>
          value !== "" && !(Array.isArray(value) && value.length === 0),
      );
    case "value": {
      const local = relative(resource, filter.path);
      const items = local === undefined ? undefined : lookup(resource, local);
      return (
        Array.isArray(items) &&
        items.some((item) => isRecord(item) && matches(item, filter.filter))
      );
    }
    case "eq":
    case "ne":
    case "co":
    case "sw":
    case "ew":
    case "gt":
    case "ge":
    case "lt":
    case "le": {
      const values = valuesAt(resource, filter.path);
      if (values.length === 0) return filter.op === "ne";
      return values.some((value) =>
        compare(filter.op, value, filter.value, filter.path),
      );
    }
    default: {
      const unreachable: never = filter;
      throw new ScimFilterError(
        `Unknown filter ${JSON.stringify(unreachable)}`,
      );
    }
  }
}
