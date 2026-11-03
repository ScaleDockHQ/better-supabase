import { withoutComments } from "./audit-registrations.ts";
import {
  closingParen,
  NAME,
  qualified,
  splitTopLevel,
  unquote,
} from "./schema-scan.ts";

const INSERT = /* @__PURE__ */ new RegExp(
  String.raw`\binsert\s+into\s+(${NAME}(?:\s*\.\s*${NAME})?)\s*\(`,
  "gi",
);

const UPDATE = /* @__PURE__ */ new RegExp(
  String.raw`\bupdate\s+(?:only\s+)?(${NAME}(?:\s*\.\s*${NAME})?)`,
  "gi",
);

const LITERAL = /'((?:[^']|'')*)'/g;

const UNSUPPORTED = "better_supabase.value_unsupported";

const DO_UPDATE = /\bdo\s+update\s+set\b/i;

function isWord(char: string | undefined): boolean {
  return char !== undefined && /[A-Za-z0-9_$]/.test(char);
}

function skipSpace(text: string, start: number): number {
  let at = start;

  while (at < text.length && /\s/.test(text[at]!)) {
    at += 1;
  }

  return at;
}

/** The index of `word` at parenthesis depth 0 and outside a string. */
function topLevelIndexOf(text: string, word: string, start: number): number {
  const lower = word.toLowerCase();
  let depth = 0;
  let quote: string | undefined;

  for (let i = start; i < text.length; i += 1) {
    const char = text[i]!;

    if (quote !== undefined) {
      if (char === quote) {
        quote = undefined;
      }

      continue;
    }

    if (char === "'" || char === '"') {
      quote = char;
      continue;
    }

    if (char === "(") {
      depth += 1;
      continue;
    }

    if (char === ")") {
      depth = Math.max(depth - 1, 0);
      continue;
    }

    if (
      depth === 0 &&
      text.slice(i, i + lower.length).toLowerCase() === lower &&
      !isWord(text[i - 1]) &&
      !isWord(text[i + lower.length])
    ) {
      return i;
    }
  }

  return -1;
}

/** The index of a top-level `char`. */
function topLevelChar(text: string, char: string, start: number): number {
  let depth = 0;
  let quote: string | undefined;

  for (let i = start; i < text.length; i += 1) {
    const current = text[i]!;

    if (quote !== undefined) {
      if (current === quote) {
        quote = undefined;
      }

      continue;
    }

    if (current === "'" || current === '"') {
      quote = current;
      continue;
    }

    if (current === "(") {
      depth += 1;
      continue;
    }

    if (current === ")") {
      depth = Math.max(depth - 1, 0);
      continue;
    }

    if (depth === 0 && current === char) {
      return i;
    }
  }

  return -1;
}

function statementEnd(text: string, start: number): number {
  const end = topLevelIndexOf(text, ";", start);

  return end === -1 ? text.length : end;
}

/** The last identifier of `text`, unquoted. */
function lastName(text: string): string | undefined {
  const names = text.match(new RegExp(NAME, "g"));
  const last = names?.at(-1);

  return last === undefined ? undefined : unquote(last);
}

/** `text` without `better_supabase.value_unsupported(...)` calls. */
function withoutUnsupported(text: string): string {
  let out = text;

  for (;;) {
    const at = out.indexOf(UNSUPPORTED);

    if (at === -1) {
      return out;
    }

    const open = out.indexOf("(", at);
    const close = open === -1 ? -1 : closingParen(out, open);

    if (close === -1) {
      return out;
    }

    out = `${out.slice(0, at)}${out.slice(close + 1)}`;
  }
}

function collect(expression: string, found: string[]): void {
  for (const match of withoutComparisons(
    withoutUnsupported(expression),
  ).matchAll(LITERAL)) {
    const value = match[1]!.replaceAll("''", "'");

    if (!found.includes(value)) {
      found.push(value);
    }
  }
}

/** `text` without the literals it compares a column with. */
function withoutComparisons(text: string): string {
  return text
    .replaceAll(/(?:<>|!=|=)\s*(?:\(\s*)?'(?:[^']|'')*'(?:\s*\))?/g, "")
    .replaceAll(/\b(?:not\s+in|in|like|ilike)\s*\((?:(?!\))[\s\S])*\)/gi, "")
    .replaceAll(/\b(?:not\s+in|in|like|ilike)\s*'(?:[^']|'')*'/gi, "");
}

/** The literals the `set` list from `start` writes into `column`. */
function assignments(
  text: string,
  start: number,
  column: string,
  found: string[],
): void {
  const stops = ["from", "where", "returning"]
    .map((word) => topLevelIndexOf(text, word, start))
    .filter((index) => index !== -1);

  const end =
    stops.length === 0 ? statementEnd(text, start) : Math.min(...stops);

  for (const part of splitTopLevel(text.slice(start, end))) {
    const equals = topLevelChar(part, "=", 0);

    if (equals === -1 || lastName(part.slice(0, equals)) !== column) {
      continue;
    }

    collect(part.slice(equals + 1), found);
  }
}

/**
 * The string literals `sql` writes into `column` of `table`, from the `insert
 * into` column lists with `values` or `select`, the `update ... set`
 * assignments and the `do update set` of an upsert. Values that arrive as a
 * parameter, and literals only compared or declared, are not written.
 */
export function writtenValues(
  sql: string,
  table: string,
  column: string,
): readonly string[] {
  const text = withoutComments(sql);
  const target = qualified(table);
  const found: string[] = [];

  for (const match of text.matchAll(INSERT)) {
    if (qualified(match[1]!) !== target) {
      continue;
    }

    const open = match.index + match[0].length - 1;
    const close = closingParen(text, open);

    if (close === -1) {
      continue;
    }

    const columns = splitTopLevel(text.slice(open + 1, close)).map(lastName);
    const index = columns.indexOf(column);

    if (index === -1) {
      continue;
    }

    let at = skipSpace(text, close + 1);

    if (/^values\b/i.test(text.slice(at))) {
      at += "values".length;

      for (;;) {
        at = skipSpace(text, at);

        if (text[at] !== "(") {
          break;
        }

        const tupleClose = closingParen(text, at);

        if (tupleClose === -1) {
          break;
        }

        const expression = splitTopLevel(text.slice(at + 1, tupleClose))[index];

        if (expression !== undefined) {
          collect(expression, found);
        }

        at = skipSpace(text, tupleClose + 1);

        if (text[at] !== ",") {
          break;
        }

        at += 1;
      }
    } else if (/^select\b/i.test(text.slice(at))) {
      const from = topLevelIndexOf(text, "from", at);
      const end = from === -1 ? statementEnd(text, at) : from;

      const list = text
        .slice(at + "select".length, end)
        .replace(/^\s*(?:distinct|all)\b/i, "");

      const expression = splitTopLevel(list)[index];

      if (expression !== undefined) {
        collect(expression, found);
      }
    }

    const statement = text.slice(close, statementEnd(text, close));
    const conflict = statement.search(DO_UPDATE);

    if (conflict !== -1) {
      const doUpdate = close + conflict;
      const set = text.indexOf("set", doUpdate);

      if (set !== -1) {
        assignments(text, set + "set".length, column, found);
      }
    }
  }

  for (const match of text.matchAll(UPDATE)) {
    if (qualified(match[1]!) !== target) {
      continue;
    }

    let at = skipSpace(text, match.index + match[0].length);

    if (!/^set\b/i.test(text.slice(at))) {
      if (/^as\b/i.test(text.slice(at))) {
        at = skipSpace(text, at + "as".length);
      }

      const alias = new RegExp(NAME, "g");
      alias.lastIndex = at;
      const name = alias.exec(text);

      if (name === null) {
        continue;
      }

      at = skipSpace(text, name.index + name[0].length);

      if (!/^set\b/i.test(text.slice(at))) {
        continue;
      }
    }

    assignments(text, at + "set".length, column, found);
  }

  return found;
}
