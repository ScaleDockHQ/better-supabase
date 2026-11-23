import type { ScanToken } from "@supabase/pg-parser";

import type { Source } from "./source.ts";

/** One SQL statement and the line (1-based) it starts on. */
export interface SqlStatement {
  /** The statement without its comments and the closing semicolon. */
  readonly text: string;
  readonly line: number;
}

/**
 * The statement `tokens` make, with a line comment dropped and a block comment
 * turned into one space, so the text reads like the source without notes.
 */
function textOf(
  source: Source,
  first: ScanToken,
  last: ScanToken,
): SqlStatement {
  let text = "";
  let at = first.start;

  for (const comment of source.comments) {
    if (comment.start < at || comment.end > last.end) {
      continue;
    }

    text += source.slice(at, comment.start);

    if (comment.kind === "C_COMMENT") {
      text += " ";
    }

    at = comment.end;
  }

  text += source.slice(at, last.end);

  return { text: text.trim(), line: source.lineAt(first.start) };
}

/**
 * The statements of a scanned text, split at the semicolons the scanner reports
 * outside quotes, dollar quotes and comments.
 *
 * @param source - The scanned text.
 * @returns The statements in source order, empty ones left out.
 */
export function statementsFrom(source: Source): SqlStatement[] {
  const statements: SqlStatement[] = [];
  let first: ScanToken | undefined;
  let last: ScanToken | undefined;

  for (const token of source.tokens) {
    if (token.text === ";" && token.kind !== "SCONST") {
      if (first !== undefined && last !== undefined) {
        statements.push(textOf(source, first, last));
      }

      first = undefined;
      last = undefined;
      continue;
    }

    first ??= token;
    last = token;
  }

  if (first !== undefined && last !== undefined) {
    statements.push(textOf(source, first, last));
  }

  return statements;
}

/**
 * The statements of a scanned text as written: each runs from the end of the
 * previous semicolon through its own, so comments and the semicolon stay. A
 * tail with only comments is kept as a last entry.
 *
 * @param source - The scanned text.
 * @returns The raw statements in source order.
 */
export function rawStatementsFrom(source: Source): string[] {
  const found: string[] = [];
  let start = 0;

  for (const token of source.tokens) {
    if (token.text === ";" && token.kind !== "SCONST") {
      found.push(source.slice(start, token.end));
      start = token.end;
    }
  }

  const tail = source.slice(start, source.bytes.length);

  if (tail.trim() !== "") {
    found.push(tail);
  }

  return found;
}

/**
 * The text with each line comment dropped (its newline stays) and each block
 * comment turned into one space, strings, quoted names and dollar quotes
 * untouched.
 *
 * @param source - The scanned text.
 * @returns The text without comments.
 */
export function blankedFrom(source: Source): string {
  let text = "";
  let at = 0;

  for (const comment of source.comments) {
    text += source.slice(at, comment.start);

    if (comment.kind === "C_COMMENT") {
      text += " ";
    }

    at = comment.end;
  }

  return text + source.slice(at, source.bytes.length);
}
