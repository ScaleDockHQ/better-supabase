import type { ScanToken } from "@supabase/pg-parser";

/** A SQL text with its tokens, so facts can quote the source they came from. */
export class Source {
  readonly bytes: Buffer;
  /** Tokens without comments. */
  readonly tokens: readonly ScanToken[];
  readonly comments: readonly ScanToken[];
  readonly #lineStarts: number[] = [0];

  constructor(text: string, scanned: readonly ScanToken[]) {
    this.bytes = Buffer.from(text, "utf-8");
    this.tokens = scanned.filter(
      (token) => token.kind !== "SQL_COMMENT" && token.kind !== "C_COMMENT",
    );
    this.comments = scanned.filter(
      (token) => token.kind === "SQL_COMMENT" || token.kind === "C_COMMENT",
    );

    for (let at = 0; at < this.bytes.length; at += 1) {
      if (this.bytes[at] === 0x0a) {
        this.#lineStarts.push(at + 1);
      }
    }
  }

  /** The 1-based line of a byte offset. */
  lineAt(offset: number): number {
    let low = 0;
    let high = this.#lineStarts.length - 1;

    while (low < high) {
      const middle = Math.ceil((low + high) / 2);

      if (this.#lineStarts[middle]! <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }

    return low + 1;
  }

  /** The 1-based column of a byte offset. */
  columnAt(offset: number): number {
    return offset - this.#lineStarts[this.lineAt(offset) - 1]! + 1;
  }

  slice(start: number, end: number): string {
    return this.bytes.toString("utf-8", start, end);
  }

  /** The index of the first token that starts at or after `offset`. */
  tokenAt(offset: number): number {
    let low = 0;
    let high = this.tokens.length;

    while (low < high) {
      const middle = Math.floor((low + high) / 2);

      if (this.tokens[middle]!.start < offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }

    return low;
  }

  /** The tokens that start inside `[start, end)`. */
  within(start: number, end: number): readonly ScanToken[] {
    const first = this.tokenAt(start);
    let last = first;

    while (last < this.tokens.length && this.tokens[last]!.start < end) {
      last += 1;
    }

    return this.tokens.slice(first, last);
  }

  /**
   * The source between the first and last of `tokens` as written, with the
   * comments between them dropped and whitespace collapsed.
   */
  raw(tokens: readonly ScanToken[]): string {
    const first = tokens[0];
    const last = tokens.at(-1);

    if (first === undefined || last === undefined) {
      return "";
    }

    const bytes = Buffer.from(this.bytes.subarray(first.start, last.end));

    for (const comment of this.comments) {
      if (comment.start >= first.start && comment.end <= last.end) {
        bytes.fill(
          0x20,
          comment.start - first.start,
          comment.end - first.start,
        );
      }
    }

    return bytes.toString("utf-8").replaceAll(/\s+/g, " ").trim();
  }

  /** `tokens` as text: identifiers unquoted, spacing collapsed to one space. */
  render(tokens: readonly ScanToken[]): string {
    let out = "";

    for (const [at, token] of tokens.entries()) {
      if (at > 0) {
        const gap = this.slice(tokens[at - 1]!.end, token.start);

        out += gap === "" ? "" : " ";
      }

      out += wordText(token);
    }

    return out;
  }
}

/** A word is an identifier or a keyword: unquoted names fold to lower case. */
function wordText(token: ScanToken): string {
  if (token.kind === "IDENT" || token.keywordKind !== "none") {
    return token.text.startsWith('"')
      ? token.text.slice(1, -1).replaceAll('""', '"')
      : token.text.toLowerCase();
  }

  return token.text;
}

/**
 * The tokens inside the first balanced parentheses at or after `from`, as
 * `[open, close]` token indexes, or `undefined`.
 */
export function parenthesized(
  tokens: readonly ScanToken[],
  from: number,
): readonly [number, number] | undefined {
  let open = from;

  while (open < tokens.length && tokens[open]!.text !== "(") {
    open += 1;
  }

  let depth = 0;

  for (let at = open; at < tokens.length; at += 1) {
    const text = tokens[at]!.text;

    if (text === "(") {
      depth += 1;
    } else if (text === ")") {
      depth -= 1;

      if (depth === 0) {
        return [open, at];
      }
    }
  }

  return undefined;
}

/** `tokens` split at the commas that are outside any parentheses. */
export function topLevelParts(
  tokens: readonly ScanToken[],
): readonly (readonly ScanToken[])[] {
  const parts: ScanToken[][] = [[]];
  let depth = 0;

  for (const token of tokens) {
    if (token.text === "(" || token.text === "[") {
      depth += 1;
    } else if (token.text === ")" || token.text === "]") {
      depth -= 1;
    }

    if (token.text === "," && depth === 0) {
      parts.push([]);
    } else {
      parts.at(-1)!.push(token);
    }
  }

  return parts.filter((part) => part.length > 0);
}
