import { withoutComments } from "./audit-registrations.ts";
import {
  closingParen,
  NAME,
  qualified,
  splitTopLevel,
  unquote,
} from "./schema-scan.ts";

const TABLE_NAME = String.raw`(${NAME}(?:\s*\.\s*${NAME})?)`;

const INSERT = /* @__PURE__ */ new RegExp(
  String.raw`\binsert\s+into\s+${TABLE_NAME}(?:\s+as\s+${NAME})?\s*\(`,
  "gi",
);

const UPDATE = /* @__PURE__ */ new RegExp(
  String.raw`\bupdate\s+(?:only\s+)?${TABLE_NAME}(?:\s+(?:as\s+)?(?!set\b)${NAME})?\s+set\b`,
  "gi",
);

const SELECT_END = ["from", "where", "on", "returning", "union", "group"];
const SET_END = ["from", "where", "returning", "on"];

const LITERAL = /^(?:'(?:[^']|'')*'|null|default)$/i;

const COPY = /* @__PURE__ */ new RegExp(
  String.raw`^(?:excluded|old|new)\s*\.\s*(${NAME})$`,
  "i",
);

function partEnd(text: string, start: number, ends: readonly string[]): number {
  const keyword = new RegExp(`^(?:${ends.join("|")})\\b`, "i");
  let depth = 0;
  let quote: string | undefined;

  for (let i = start; i < text.length; i += 1) {
    const char = text[i]!;

    if (quote) {
      if (char === quote) {
        quote = undefined;
      }
    } else if (char === "'" || char === '"') {
      quote = char;
    } else if (char === "(") {
      depth += 1;
    } else if (char === ")") {
      if (depth === 0) {
        return i;
      }

      depth -= 1;
    } else if (char === ";" && depth === 0) {
      return i;
    } else if (
      depth === 0 &&
      !/[\w$."]/.test(text[i - 1] ?? " ") &&
      keyword.test(text.slice(i, i + 12))
    ) {
      return i;
    }
  }

  return text.length;
}

function writes(
  found: Map<string, Set<string>>,
  table: string,
  column: string,
  value: string,
): void {
  const expression = value.trim();
  const copied = COPY.exec(expression)?.[1];

  if (
    LITERAL.test(expression) ||
    (copied !== undefined && unquote(copied) === column)
  ) {
    return;
  }

  const columns = found.get(table) ?? new Set<string>();
  columns.add(column);
  found.set(table, columns);
}

function assignments(
  found: Map<string, Set<string>>,
  table: string,
  text: string,
): void {
  for (const part of splitTopLevel(text)) {
    const assignment = new RegExp(`^\\s*(${NAME})\\s*=([\\s\\S]*)$`).exec(part);

    if (assignment !== null) {
      writes(found, table, unquote(assignment[1]!), assignment[2]!);
    }
  }
}

/**
 * The columns each table gets a computed value in: an `insert`, an `update ...
 * set` or an `on conflict do update` that writes anything but a string literal,
 * `null`, `default` or the same column of `excluded`, `old` or `new`. The keys
 * are `schema.table`, unquoted.
 */
export function computedWrites(
  sql: string,
): ReadonlyMap<string, ReadonlySet<string>> {
  const text = withoutComments(sql);
  const found = new Map<string, Set<string>>();

  for (const match of text.matchAll(INSERT)) {
    const table = qualified(match[1]!);
    const open = match.index + match[0].length - 1;
    const close = closingParen(text, open);

    if (close === -1) {
      continue;
    }

    const columns = splitTopLevel(text.slice(open + 1, close)).map((column) =>
      unquote(column.trim()),
    );

    const rest = text.slice(close + 1);
    const source = /^\s*(values\s*\(|select\b)/i.exec(rest);

    if (source === null) {
      continue;
    }

    const start = close + 1 + source[0].length;

    const end = source[1]!.toLowerCase().startsWith("values")
      ? closingParen(text, start - 1)
      : partEnd(text, start, SELECT_END);

    const values = splitTopLevel(text.slice(start, end === -1 ? start : end));

    for (const [index, column] of columns.entries()) {
      writes(found, table, column, values[index] ?? "");
    }

    const conflict =
      /^[^;]*?\bon\s+conflict\b[^;]*?\bdo\s+update\s+set\b/i.exec(
        text.slice(end === -1 ? start : end),
      );

    if (conflict !== null) {
      const from = (end === -1 ? start : end) + conflict[0].length;
      assignments(found, table, text.slice(from, partEnd(text, from, SET_END)));
    }
  }

  for (const match of text.matchAll(UPDATE)) {
    const table = qualified(match[1]!);
    const start = match.index + match[0].length;
    assignments(found, table, text.slice(start, partEnd(text, start, SET_END)));
  }

  return found;
}
