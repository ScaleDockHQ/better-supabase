import { withoutComments } from "./audit-registrations.ts";
import {
  closingParen,
  NAME,
  qualified,
  splitTopLevel,
  unquote,
} from "./schema-scan.ts";

const INSERT = /* @__PURE__ */ new RegExp(
  String.raw`\binsert\s+into\s+(${NAME}(?:\s*\.\s*${NAME})?)(?:\s+as\s+${NAME})?\s*\(`,
  "gi",
);

const UPDATE = /* @__PURE__ */ new RegExp(
  String.raw`\bupdate\s+(?:only\s+)?(${NAME}(?:\s*\.\s*${NAME})?)`,
  "gi",
);

const TRIGGER = /* @__PURE__ */ new RegExp(
  String.raw`\bcreate\s+(?:or\s+replace\s+)?(?:constraint\s+)?trigger\s+${NAME}\s+(?:before|instead\s+of)\b[^;]*?\bon\s+(${NAME}(?:\s*\.\s*${NAME})?)[^;]*?\bexecute\s+(?:function|procedure)\s+(${NAME}(?:\s*\.\s*${NAME})?)\s*\(`,
  "gi",
);

const FUNCTION = /* @__PURE__ */ new RegExp(
  String.raw`\bcreate\s+(?:or\s+replace\s+)?function\s+(${NAME}(?:\s*\.\s*${NAME})?)\s*\(`,
  "gi",
);

const NEW_ASSIGNMENT = /* @__PURE__ */ new RegExp(
  String.raw`\bnew\s*\.\s*(${NAME})\s*:=`,
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

function lastName(text: string): string | undefined {
  const names = text.match(new RegExp(NAME, "g"));
  const last = names?.at(-1);

  return last === undefined ? undefined : unquote(last);
}

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

function withoutComparisons(text: string): string {
  return text
    .replaceAll(/(?:<>|!=|=)\s*(?:\(\s*)?'(?:[^']|'')*'(?:\s*\))?/g, "")
    .replaceAll(/\b(?:not\s+in|in|like|ilike)\s*\((?:(?!\))[\s\S])*\)/gi, "")
    .replaceAll(/\b(?:not\s+in|in|like|ilike)\s*'(?:[^']|'')*'/gi, "");
}

function assignments(
  text: string,
  start: number,
  column: string,
  found: string[],
): void {
  const stops = ["from", "where", "returning"]
    .map((word) => topLevelIndexOf(text, word, start))
    .filter((index) => index !== -1);

  const end = Math.min(statementEnd(text, start), ...stops);

  for (const part of splitTopLevel(text.slice(start, end))) {
    const equals = topLevelChar(part, "=", 0);

    if (equals === -1 || lastName(part.slice(0, equals)) !== column) {
      continue;
    }

    collect(part.slice(equals + 1), found);
  }
}

function functionBody(text: string, name: string): string | undefined {
  for (const match of text.matchAll(FUNCTION)) {
    if (qualified(match[1]!) !== name) {
      continue;
    }

    const rest = text.slice(match.index + match[0].length);
    const open = /\$([A-Za-z_]*)\$/.exec(rest);

    if (open === null) {
      return undefined;
    }

    const start = open.index + open[0].length;
    const close = rest.indexOf(open[0], start);

    return close === -1 ? undefined : rest.slice(start, close);
  }

  return undefined;
}

function triggerWrites(
  text: string,
  target: string,
  column: string,
  found: string[],
): void {
  for (const match of text.matchAll(TRIGGER)) {
    if (qualified(match[1]!) !== target) {
      continue;
    }

    const body = functionBody(text, qualified(match[2]!));

    if (body === undefined) {
      continue;
    }

    for (const assignment of body.matchAll(NEW_ASSIGNMENT)) {
      if (unquote(assignment[1]!) !== column) {
        continue;
      }

      const start = assignment.index + assignment[0].length;

      collect(body.slice(start, statementEnd(body, start)), found);
    }
  }
}

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

      const end =
        from === -1
          ? statementEnd(text, at)
          : Math.min(from, statementEnd(text, at));

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
      const set = text.toLowerCase().indexOf("set", doUpdate);

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

  triggerWrites(text, target, column, found);

  return found;
}
