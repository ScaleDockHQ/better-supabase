import type { ScanToken } from "@supabase/pg-parser";

import { Source } from "./source.ts";
import { statementEnds } from "./statement-ends.ts";

/**
 * One token of the code of a SQL text. Comments are gone, a string literal is
 * one `string` token whose `value` is the text between the quotes, and a
 * dollar-quoted body (a function body, a `do` block) is read as code in place,
 * one `depth` deeper.
 */
export interface CodeToken {
  /**
   * `word` is a bare identifier or keyword, lowercased in `text`; `quoted` is a
   * double-quoted name (`value` has no quotes); `string` and `number` are
   * literals; `punct` is an operator or a bracket.
   */
  readonly kind: "number" | "punct" | "quoted" | "string" | "word";
  readonly text: string;
  readonly value: string;
  /** The line in the file this token starts on, 1-based. */
  readonly line: number;
  /** 0 at the top of the file, one more inside each dollar-quoted body. */
  readonly depth: number;
}

/** The tokens of one statement, up to its top-level semicolon. */
export interface CodeStatement {
  readonly tokens: readonly CodeToken[];
  readonly line: number;
}

export type Scan = (text: string) => Promise<readonly ScanToken[]>;

const stringValue = (text: string): string => {
  const open = text.indexOf("'");

  return text.slice(open + 1, -1).replaceAll("''", "'");
};

/**
 * One copy of each short token text per read: a large schema repeats its
 * keywords, names and operators millions of times.
 */
type Interned = Map<string, string>;

const INTERNED_LENGTH_MAX = 64;

const interned = (strings: Interned, text: string): string => {
  if (text.length > INTERNED_LENGTH_MAX) {
    return text;
  }

  const known = strings.get(text);

  if (known !== undefined) {
    return known;
  }

  strings.set(text, text);

  return text;
};

function classify(
  source: Source,
  token: ScanToken,
  strings: Interned,
): Pick<CodeToken, "kind" | "text" | "value"> | "dollar" {
  const text = interned(strings, source.slice(token.start, token.end));

  if (token.kind.endsWith("SCONST") || token.kind === "BCONST") {
    return text.startsWith("$")
      ? "dollar"
      : { kind: "string", text, value: stringValue(text) };
  }

  if (token.kind === "IDENT" && text.startsWith('"')) {
    return {
      kind: "quoted",
      text,
      value: interned(strings, text.slice(1, -1).replaceAll('""', '"')),
    };
  }

  if (token.kind === "IDENT" || token.keywordKind !== "none") {
    return {
      kind: "word",
      text: interned(strings, text.toLowerCase()),
      value: text,
    };
  }

  if (token.kind === "ICONST" || token.kind === "FCONST") {
    return { kind: "number", text, value: text };
  }

  return { kind: "punct", text, value: text };
}

async function expand(
  text: string,
  scan: Scan,
  first: number,
  depth: number,
  out: CodeToken[],
  strings: Interned,
): Promise<void> {
  const scanned = await scan(text);
  const source = new Source(text, scanned);

  for (const token of source.tokens) {
    const line = first + source.lineAt(token.start) - 1;
    const read = classify(source, token, strings);

    if (read !== "dollar") {
      out.push({
        kind: read.kind,
        text: read.text,
        value: read.value,
        line,
        depth,
      });
      continue;
    }

    const whole = source.slice(token.start, token.end);
    const tag = whole.indexOf("$", 1) + 1;
    const inner = whole.slice(tag, whole.length - tag);

    const opening = first + source.lineAt(token.start) - 1;
    const bodyLine = opening + whole.slice(0, tag).split("\n").length - 1;

    try {
      // The body of a function is plpgsql, which the SQL scanner tokenizes
      // well enough to find calls, strings and statement ends.
      await expand(inner, scan, bodyLine, depth + 1, out, strings);
    } catch {
      // A dollar-quoted text that is not code (an unterminated quote inside a
      // message, a template) stays one string.
      out.push({ kind: "string", text: whole, value: inner, line, depth });
    }
  }
}

/**
 * The statements of a text as code tokens, so a rule reads calls, names and
 * strings and never a comment or the inside of a literal.
 *
 * @param text - The SQL text.
 * @param scan - The pg-parser scanner.
 * @returns The statements, split at the semicolons outside bodies.
 */
export async function codeStatementsFrom(
  text: string,
  scan: Scan,
): Promise<readonly CodeStatement[]> {
  const tokens: CodeToken[] = [];

  await expand(text, scan, 1, 0, tokens, new Map());

  const top = tokens.flatMap((token, at) =>
    token.depth === 0 ? [{ token, at }] : [],
  );

  const ends = new Set(
    [
      ...statementEnds(
        top.map(({ token }) =>
          token.kind === "word" || token.kind === "punct" ? token.text : "",
        ),
      ),
    ].map((index) => top[index]!.at),
  );

  const statements: CodeStatement[] = [];
  let current: CodeToken[] = [];

  const close = (): void => {
    const first = current[0];

    if (first !== undefined) {
      statements.push({ tokens: current, line: first.line });
    }

    current = [];
  };

  for (const [at, token] of tokens.entries()) {
    if (ends.has(at)) {
      close();
    } else {
      current.push(token);
    }
  }

  close();

  return statements;
}

/** Whether `tokens` hold the words in `words`, one after another, from `at`. */
export function wordsAt(
  tokens: readonly CodeToken[],
  at: number,
  ...words: readonly string[]
): boolean {
  return words.every(
    (word, offset) =>
      tokens[at + offset]?.kind === "word" &&
      tokens[at + offset]?.text === word,
  );
}

/** The index of the first run of `words` at or after `from`, or -1. */
export function indexOfWords(
  tokens: readonly CodeToken[],
  from: number,
  ...words: readonly string[]
): number {
  for (let at = from; at < tokens.length; at += 1) {
    if (wordsAt(tokens, at, ...words)) {
      return at;
    }
  }

  return -1;
}

/**
 * The possibly schema-qualified name that starts at `at` (`name`, `s.name`,
 * `"S"."Name"`), as written without quotes, with the index after it.
 */
export function nameAt(
  tokens: readonly CodeToken[],
  at: number,
): { readonly parts: readonly string[]; readonly next: number } | undefined {
  const parts: string[] = [];
  let next = at;

  for (;;) {
    const token = tokens[next];

    if (token?.kind !== "word" && token?.kind !== "quoted") {
      break;
    }

    parts.push(token.value);
    next += 1;

    if (tokens[next]?.text !== ".") {
      break;
    }

    next += 1;
  }

  return parts.length === 0 ? undefined : { parts, next };
}
