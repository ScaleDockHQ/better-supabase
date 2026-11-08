import { closingParen, maskSql } from "./policy.ts";
import { shortHash } from "./shared.ts";

const MAX_NAME = 63;

/**
 * The name a generated policy carries: `bsb_` ahead of the name a module wrote,
 * shortened with a hash when it passes 63 bytes (ADR 0272). A name that already
 * starts with `bsb_` and fits stays as it is.
 */
export function bsbPolicyName(name: string): string {
  const full = name.startsWith("bsb_") ? name : `bsb_${name}`;

  return full.length <= MAX_NAME
    ? full
    : `${full.slice(0, MAX_NAME - 9)}_${shortHash(full)}`;
}

const STATEMENT =
  /\b(create|drop|alter)\s+policy\s+(if\s+exists\s+)?(?=("(?:[^"]|"")+"|[a-z_][\w$]*))/gi;

interface Found {
  readonly kind: string;
  /** `[start, end)` of the name as written, quotes included. */
  readonly span: readonly [number, number];
  readonly name: string;
}

function found(sql: string, masked: string): Found[] {
  const out: Found[] = [];

  for (const match of masked.matchAll(STATEMENT)) {
    const start = match.index + match[0].length;
    const rest = sql.slice(start);
    const quoted = /^"((?:[^"]|"")+)"/.exec(rest);
    const bare = /^[a-z_][\w$]*/i.exec(rest);

    if (quoted !== null) {
      out.push({
        kind: match[1]!.toLowerCase(),
        span: [start, start + quoted[0].length],
        name: quoted[1]!.replaceAll('""', '"'),
      });
    } else if (bare !== null) {
      out.push({
        kind: match[1]!.toLowerCase(),
        span: [start, start + bare[0].length],
        name: bare[0].toLowerCase(),
      });
    }
  }

  return out;
}

const PLAIN = /^[a-z_][a-z0-9_$]*$/;

const write = (name: string): string =>
  PLAIN.test(name) ? name : `"${name.replaceAll('"', '""')}"`;

interface Edit {
  readonly from: number;
  readonly to: number;
  readonly text: string;
}

function policyEdits(sql: string, masked: string): Edit[] {
  const all = found(sql, masked);

  const created = new Set(
    all.filter((entry) => entry.kind === "create").map((entry) => entry.name),
  );

  return all.flatMap((entry): Edit[] => {
    const next = bsbPolicyName(entry.name);

    return created.has(entry.name) && next !== entry.name
      ? [{ from: entry.span[0], to: entry.span[1], text: write(next) }]
      : [];
  });
}

function applyEdits(sql: string, edits: readonly Edit[]): string {
  let out = "";
  let cursor = 0;

  for (const edit of edits.toSorted((a, b) => a.from - b.from)) {
    if (edit.from < cursor) {
      continue;
    }

    out += sql.slice(cursor, edit.from) + edit.text;
    cursor = edit.to;
  }

  return out + sql.slice(cursor);
}

const maskOf = (sql: string): string => maskSql(sql, { dollarBodies: "scan" });

/**
 * `sql` with every policy it creates named `bsb_*`, in the `create`, `alter`
 * and `drop` statements alike. A `drop policy if exists` for a name the text
 * never creates stays: it removes a policy an earlier release wrote.
 */
export function bsbPolicyNames(sql: string): string {
  return applyEdits(sql, policyEdits(sql, maskOf(sql)));
}

/** `bsb_` ahead of `name`, shortened with a hash when it passes 63 bytes. */
export function bsbConstraintName(name: string): string {
  const full = name.startsWith("bsb_") ? name : `bsb_${name}`;

  return full.length <= MAX_NAME
    ? full
    : `${full.slice(0, MAX_NAME - 9)}_${shortHash(full)}`;
}

const SQL_NAME = String.raw`(?:"_+"|[a-z_][\w$]*)`;
const QUALIFIED = String.raw`${SQL_NAME}(?:\s*\.\s*${SQL_NAME})?`;

const TABLE_STATEMENT =
  /\b(create\s+(?:unlogged\s+|temp(?:orary)?\s+)?table|alter\s+table)\b/gi;

const CREATE_HEAD = new RegExp(
  String.raw`^create\s+(?:unlogged\s+|temp(?:orary)?\s+)?table\s+(?:if\s+not\s+exists\s+)?(${QUALIFIED})\s*\(`,
  "i",
);

const ALTER_HEAD = new RegExp(
  String.raw`^alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?(${QUALIFIED})\s`,
  "i",
);

const EXPLICIT_CHECK = new RegExp(
  String.raw`\bconstraint\s+(${SQL_NAME})\s+check\s*\(`,
  "gi",
);

const CONSTRAINT_REFERENCE = new RegExp(
  String.raw`\b(?:drop|validate)\s+constraint\s+(?:if\s+exists\s+)?(${SQL_NAME})`,
  "gi",
);

const NAMED_CONSTRAINT = new RegExp(
  String.raw`\bconstraint\s+(${SQL_NAME})(?![\w$"])`,
  "gi",
);

const CHECK_OPEN = /\bcheck\s*\(/gi;

const TABLE_ITEM =
  /^(?:constraint\s+\S+\s+)?(?:check|unique|primary|foreign|exclude|like)\b/i;

interface TableState {
  readonly used: Set<string>;
  readonly columns: Set<string>;
  /** Whether the text creates the table, so `columns` lists them all. */
  complete: boolean;
}

/** The ranges of `masked` between the commas outside parentheses. */
function splitRanges(
  masked: string,
  from: number,
  to: number,
): [number, number][] {
  const ranges: [number, number][] = [];
  let depth = 0;
  let start = from;

  for (let at = from; at < to; at += 1) {
    const char = masked[at];

    if (char === "(") {
      depth += 1;
    } else if (char === ")") {
      depth -= 1;
    } else if (char === "," && depth === 0) {
      ranges.push([start, at]);
      start = at + 1;
    }
  }

  return [...ranges, [start, to]];
}

/**
 * The end of the statement that starts at `from`: its semicolon or the text's
 * end.
 */
function statementEnd(masked: string, from: number): number {
  let depth = 0;

  for (let at = from; at < masked.length; at += 1) {
    const char = masked[at];

    if (char === "(") {
      depth += 1;
    } else if (char === ")") {
      depth -= 1;
    } else if (char === ";" && depth <= 0) {
      return at;
    }
  }

  return masked.length;
}

const unquote = (name: string): string =>
  name.startsWith('"') ? name.slice(1, -1).replaceAll('""', '"') : name;

/** The unquoted last part of a possibly qualified name of `sql`. */
function lastPart(sql: string, from: number, to: number): string {
  const text = sql.slice(from, to);
  const parts = text.match(/"(?:[^"]|"")+"|[^.\s]+/g) ?? [text];

  return unquote(parts.at(-1) ?? text).toLowerCase();
}

/**
 * `sql` with every check constraint of a table statement named `bsb_*`: the
 * checks Postgres would name itself take the name it would have chosen with
 * `bsb_` in front (`<table>_<column>_check` for a check that reads one column,
 * `<table>_check` for any other, `...1`, `...2` on a clash), and the checks a
 * module names get the prefix, in their `add`, `drop` and `validate` statements
 * and in the `conname = '...'` tests of a guard (ADR 0273).
 */
export function bsbCheckNames(sql: string): string {
  return applyEdits(sql, checkEdits(sql, maskOf(sql)));
}

/** The prefixes `bsbPolicyNames` and `bsbCheckNames` write, over one scan. */
export function bsbNames(sql: string): string {
  const masked = maskOf(sql);

  return applyEdits(sql, [
    ...policyEdits(sql, masked),
    ...checkEdits(sql, masked),
  ]);
}

function checkEdits(sql: string, masked: string): Edit[] {
  const edits: Edit[] = [];
  const tables = new Map<string, TableState>();

  const state = (table: string): TableState => {
    const known = tables.get(table);

    if (known !== undefined) {
      return known;
    }

    const created: TableState = {
      used: new Set<string>(),
      columns: new Set<string>(),
      complete: false,
    };

    tables.set(table, created);

    return created;
  };

  // The checks a module names itself, by the name it wrote.
  const explicit = new Map<string, string>();

  for (const match of masked.matchAll(EXPLICIT_CHECK)) {
    const at = match.index + match[0].indexOf(match[1]!, "constraint".length);
    const name = unquote(sql.slice(at, at + match[1]!.length));

    if (!name.startsWith("bsb_")) {
      explicit.set(name.toLowerCase(), bsbConstraintName(name));
    }
  }

  const renameAt = (from: number, to: number): string | undefined => {
    const name = unquote(sql.slice(from, to));
    const next = explicit.get(name.toLowerCase());

    if (next === undefined) {
      return undefined;
    }

    edits.push({ from, to, text: write(next) });

    return next;
  };

  const varsOf = (
    open: number,
    close: number,
    columns: ReadonlySet<string>,
    complete: boolean,
  ): string[] => {
    const found = new Set<string>();

    for (const token of masked
      .slice(open + 1, close)
      .matchAll(/"_+"|[a-z_][\w$]*/gi)) {
      const at = open + 1 + token.index;
      const word = token[0];

      if (word.startsWith('"')) {
        const name = unquote(sql.slice(at, at + word.length)).toLowerCase();

        if (!complete || columns.has(name)) {
          found.add(name);
        }
      } else if (
        columns.has(word.toLowerCase()) &&
        !/^\s*\(/.test(masked.slice(at + word.length, at + word.length + 3)) &&
        !/(?:\.|::)\s*$/.test(masked.slice(Math.max(0, at - 3), at))
      ) {
        found.add(word.toLowerCase());
      }
    }

    return [...found];
  };

  const nameCheck = (
    table: string,
    tableState: TableState,
    open: number,
    close: number,
  ): string => {
    const vars = varsOf(open, close, tableState.columns, tableState.complete);

    const base =
      vars.length === 1 ? `${table}_${vars[0]!}_check` : `${table}_check`;

    let suffix = 0;
    let name = bsbConstraintName(base);

    while (tableState.used.has(name.toLowerCase())) {
      suffix += 1;
      name = bsbConstraintName(`${base}${String(suffix)}`);
    }

    tableState.used.add(name.toLowerCase());

    return name;
  };

  // Names the checks and records the constraints of one item: a column
  // definition, a table constraint or an `add` clause.
  const item = (
    table: string,
    tableState: TableState,
    from: number,
    to: number,
  ): void => {
    const named = new Set<number>();

    for (const match of masked.slice(from, to).matchAll(NAMED_CONSTRAINT)) {
      const start = from + match.index + match[0].lastIndexOf(match[1]!);
      const end = start + match[1]!.length;
      const after = masked.slice(end, to);

      if (/^\s*check\s*\(/i.test(after)) {
        const next = renameAt(start, end);
        const name = next ?? unquote(sql.slice(start, end));

        tableState.used.add(name.toLowerCase());
        named.add(end + after.search(/check/i));
      } else {
        tableState.used.add(unquote(sql.slice(start, end)).toLowerCase());
      }
    }

    for (const match of masked.slice(from, to).matchAll(CHECK_OPEN)) {
      const start = from + match.index;

      if (named.has(start)) {
        continue;
      }

      const before = masked.slice(from, start);

      if (/\bwith\s+$/i.test(before)) {
        continue;
      }

      const open = start + match[0].length - 1;
      const close = closingParen(masked, open);

      if (close === -1 || close > to) {
        continue;
      }

      const name = nameCheck(table, tableState, open, close);

      edits.push({
        from: start,
        to: start,
        text: `constraint ${write(name)} `,
      });
    }
  };

  const spans: [number, number][] = [];

  for (const match of masked.matchAll(TABLE_STATEMENT)) {
    if (spans.some(([from, to]) => match.index >= from && match.index < to)) {
      continue;
    }

    spans.push([match.index, statementEnd(masked, match.index)]);
  }

  for (const [from, to] of spans) {
    const text = masked.slice(from, to);
    const created = CREATE_HEAD.exec(text);

    if (created !== null) {
      const nameAt = from + created[0].indexOf(created[1]!);
      const table = lastPart(sql, nameAt, nameAt + created[1]!.length);
      const tableState = state(table);
      tableState.complete = true;
      const open = from + created[0].length - 1;
      const close = closingParen(masked, open);

      if (close === -1) {
        continue;
      }

      const ranges = splitRanges(masked, open + 1, close);

      // A check may read a column that is defined after it.
      for (const [start, end] of ranges) {
        const trimmed = masked.slice(start, end).trim();

        if (trimmed === "" || TABLE_ITEM.test(trimmed)) {
          continue;
        }

        const first = new RegExp(`^${SQL_NAME}`).exec(trimmed);

        if (first !== null) {
          const at = start + masked.slice(start, end).indexOf(first[0]);

          tableState.columns.add(
            unquote(sql.slice(at, at + first[0].length)).toLowerCase(),
          );
        }
      }

      for (const [start, end] of ranges) {
        item(table, tableState, start, end);
      }

      continue;
    }

    const altered = ALTER_HEAD.exec(text);

    if (altered === null) {
      continue;
    }

    const nameAt = from + altered[0].indexOf(altered[1]!);
    const table = lastPart(sql, nameAt, nameAt + altered[1]!.length);
    const tableState = state(table);
    const bodyFrom = from + altered[0].length;

    for (const [start, end] of splitRanges(masked, bodyFrom, to)) {
      const action = masked.slice(start, end);

      const column = new RegExp(
        String.raw`^\s*add\s+column\s+(?:if\s+not\s+exists\s+)?(${SQL_NAME})`,
        "i",
      ).exec(action);

      if (column !== null) {
        const at = start + action.indexOf(column[1]!);

        tableState.columns.add(
          unquote(sql.slice(at, at + column[1]!.length)).toLowerCase(),
        );
      }

      if (/^\s*add\s+(?:column\s|constraint\s|check\s*\()/i.test(action)) {
        item(table, tableState, start, end);
      }
    }
  }

  for (const match of masked.matchAll(CONSTRAINT_REFERENCE)) {
    const start = match.index + match[0].lastIndexOf(match[1]!);

    renameAt(start, start + match[1]!.length);
  }

  if (explicit.size > 0 && sql.includes("conname")) {
    for (const match of sql.matchAll(/conname\s*=\s*'([^']*)'/gi)) {
      const next = explicit.get(match[1]!.toLowerCase());

      if (next !== undefined) {
        const from = match.index + match[0].indexOf("'");

        edits.push({
          from,
          to: from + match[1]!.length + 2,
          text: `'${next}'`,
        });
      }
    }
  }

  return edits;
}
