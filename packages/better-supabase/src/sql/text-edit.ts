/**
 * Lexical helpers the render path uses on SQL it has just generated. They read
 * no user file and carry no facts (ADR 1300).
 */

export const NAME: string = String.raw`(?:"(?:[^"]|"")+"|[A-Za-z_][\w$]*)`;

export const unquote = (name: string): string =>
  name.startsWith('"')
    ? name.slice(1, -1).replaceAll('""', '"')
    : name.toLowerCase();

export function qualified(target: string): string {
  const parts = (target.match(new RegExp(NAME, "g")) ?? []).map(unquote);

  return parts.length === 1 ? `public.${parts[0]!}` : parts.join(".");
}

const TABLE_NAME = String.raw`${NAME}(?:\s*\.\s*${NAME})?`;

export const TABLE: RegExp = /* @__PURE__ */ new RegExp(
  String.raw`\bcreate\s+(?:unlogged\s+)?table\s+(?:if\s+not\s+exists\s+)?(${NAME}(?:\s*\.\s*${NAME})?)\s*\(`,
  "gi",
);

/** `*` in a `schema.table` glob matches any run of characters. */
export function tableGlobs(globs: readonly string[]): RegExp[] {
  return globs.map(
    (glob) =>
      new RegExp(
        `^${glob
          .split("*")
          .map((part) => part.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&"))
          .join(".*")}$`,
        "i",
      ),
  );
}

export function closingParen(text: string, open: number): number {
  let depth = 0;
  let quote: string | undefined;

  for (let i = open; i < text.length; i += 1) {
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
      depth -= 1;

      if (depth === 0) {
        return i;
      }
    }
  }

  return -1;
}

export function splitTopLevel(text: string): string[] {
  const parts: string[] = [];
  let depth = 0;
  let quote: string | undefined;
  let start = 0;

  for (let i = 0; i < text.length; i += 1) {
    const char = text[i]!;

    if (quote) {
      if (char === quote) {
        quote = undefined;
      }
    } else if (char === "'" || char === '"') {
      quote = char;
    } else if (char === "(" || char === "[") {
      depth += 1;
    } else if (char === ")" || char === "]") {
      depth -= 1;
    } else if (char === "," && depth === 0) {
      parts.push(text.slice(start, i).trim());
      start = i + 1;
    }
  }

  const last = text.slice(start).trim();

  if (last !== "") {
    parts.push(last);
  }

  return parts;
}

/** An index a `create index` statement builds. */
export interface IndexStatement {
  /** The index name, unquoted, when the statement gives one. */
  readonly name: string | undefined;
  /** `schema.table`. */
  readonly table: string;
  readonly unique: boolean;
  /** `btree` unless the statement names another access method. */
  readonly method: string;
  /** Whether it has a `where`. */
  readonly partial: boolean;
  /** The `where` clause, including the keyword, when the index is partial. */
  readonly where?: string;
  /** The plain columns it leads with, up to the first expression or option. */
  readonly columns: readonly string[];
  /** Whether every key is a plain column. */
  readonly plain: boolean;
}

const INDEX_DEF = /* @__PURE__ */ new RegExp(
  String.raw`\bcreate\s+(unique\s+)?index\s+(?:concurrently\s+)?(?:if\s+not\s+exists\s+)?(?:(?!on\b)(${NAME})\s+)?on\s+(?:only\s+)?(${TABLE_NAME})\s*(?:using\s+(\w+)\s*)?\(`,
  "gi",
);

const PLAIN_KEY = /* @__PURE__ */ new RegExp(
  String.raw`^(${NAME})(?:\s+(?:asc|desc))?(?:\s+nulls\s+(?:first|last))?$`,
  "i",
);

/** The plain leading columns of an index key list, and whether all are plain. */
function indexKeys(list: string): {
  readonly columns: readonly string[];
  readonly plain: boolean;
} {
  const columns: string[] = [];

  for (const part of splitTopLevel(list)) {
    const key = PLAIN_KEY.exec(part.trim());

    if (key === null) {
      return { columns, plain: false };
    }

    columns.push(unquote(key[1]!));
  }

  return { columns, plain: true };
}

/**
 * Whether `predicate` is exactly `<column> is not null` for a column of
 * `columns`. Parentheses and the leading `where` are ignored. A partial unique
 * index with that predicate answers the same rows as a full key.
 */
export function notNullKeyPredicate(
  predicate: string | undefined,
  columns: readonly string[],
): boolean {
  if (predicate === undefined) {
    return false;
  }

  const text = predicate
    .trim()
    .replace(/^where\s+/i, "")
    .replace(/^\(+/, "")
    .replace(/\)+$/, "")
    .trim();

  const match = /^(?:"([^"]+)"|([A-Za-z_][\w$]*))\s+is\s+not\s+null$/i.exec(
    text,
  );

  const column = match?.[1] ?? match?.[2];

  return column !== undefined && columns.includes(column);
}

/** Each `create index` in `text`, which has no comments. */
export function indexStatements(text: string): IndexStatement[] {
  return [...text.matchAll(INDEX_DEF)].flatMap((match): IndexStatement[] => {
    const open = match.index + match[0].length - 1;
    const close = closingParen(text, open);

    if (close === -1) {
      return [];
    }

    const end = text.indexOf(";", close);
    const rest = text.slice(close + 1, end === -1 ? text.length : end);
    const where = /\bwhere\b[\s\S]*$/i.exec(rest)?.[0]?.trim();

    return [
      {
        name: match[2] === undefined ? undefined : unquote(match[2]),
        table: qualified(match[3]!),
        unique: match[1] !== undefined,
        method: (match[4] ?? "btree").toLowerCase(),
        partial: where !== undefined,
        ...(where === undefined ? {} : { where }),
        ...indexKeys(text.slice(open + 1, close)),
      },
    ];
  });
}

const SQL_PART = /('(?:[^']|'')*'|"(?:[^"]|"")*")/;

/**
 * `text` with keywords and unquoted names in lowercase, a quoted name that
 * needs no quotes unquoted, and spacing collapsed, so two spellings of one
 * expression compare equal. String literals keep their case.
 */
function normalizedSql(text: string): string {
  return text
    .split(SQL_PART)
    .map((part, at) => {
      if (at % 2 === 0) {
        return part.toLowerCase();
      }

      return /^"[a-z_][a-z0-9_$]*"$/.test(part) ? part.slice(1, -1) : part;
    })
    .join("")
    .replaceAll(/\s+/g, " ")
    .replaceAll(/\s*([(),])\s*/g, "$1")
    .trim();
}

/** Whether `(` at 0 closes at the last character of `text`. */
const wrapped = (text: string): boolean =>
  text.startsWith("(") && closingParen(text, 0) === text.length - 1;

/**
 * An index predicate without its `where` and the parentheses around the whole
 * of it, normalized: the file form `where a is not null` and the catalog form
 * `(a IS NOT NULL)` are equal. An absent predicate is `""`.
 */
export function normalizedPredicate(predicate: string | undefined): string {
  let text = normalizedSql((predicate ?? "").replace(/^\s*where\b/i, ""));

  while (wrapped(text)) {
    text = text.slice(1, -1).trim();
  }

  return text;
}

/**
 * A `create index` statement without its name, `concurrently` and `if not
 * exists`, normalized. Two statements with the same signature build the same
 * index, the way splinter's `duplicate_index` compares them.
 */
export function indexSignature(statement: string): string {
  const head = /\bcreate\s+(unique\s+)?index\b[\s\S]*?\bon\s/i.exec(statement);

  const rest =
    head === null
      ? statement
      : `${head[1] ?? ""}index on ${statement.slice(head.index + head[0].length)}`;

  return normalizedSql(rest.replace(/;\s*$/, ""));
}

/** A call that has `better_supabase.track_updated_at` create the trigger. */
export const TRACK_UPDATED_AT_CALL: RegExp =
  /\btrack_updated_at\s*\(\s*'((?:[\w$]+\.)?[\w$]+)'/gi;

/** `text` with comments blanked out, string and identifier quotes kept. */
export function withoutComments(text: string): string {
  let out = "";
  let index = 0;

  while (index < text.length) {
    const char = text[index]!;
    const next = text[index + 1];

    if (char === "'" || char === '"') {
      const end = closing(text, index, char);
      out += text.slice(index, end);
      index = end;
    } else if (char === "-" && next === "-") {
      const end = text.indexOf("\n", index);
      index = end === -1 ? text.length : end;
    } else if (char === "/" && next === "*") {
      const end = text.indexOf("*/", index + 2);
      index = end === -1 ? text.length : end + 2;
      out += " ";
    } else {
      out += char;
      index += 1;
    }
  }

  return out;
}

/**
 * The index after the quote that closes the one at `start`; doubled quotes
 * escape.
 */
function closing(text: string, start: number, quote: string): number {
  let index = start + 1;

  while (index < text.length) {
    if (text[index] === quote) {
      if (text[index + 1] !== quote) {
        return index + 1;
      }

      index += 2;
    } else {
      index += 1;
    }
  }

  return text.length;
}
