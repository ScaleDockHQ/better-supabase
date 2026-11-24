import type { Comment, ParseResult, Program } from "oxc-parser";

import { parseSync } from "oxc-parser";

import { CliError } from "../core/errors.ts";

/** One parsed TypeScript module: the tree, its comments and the text. */
export interface ParsedModule {
  readonly program: Program;
  readonly comments: readonly Comment[];
  readonly text: string;
}

/** The 1-based line and column of `offset` in `text`. */
export function lineColumn(
  text: string,
  offset: number,
): { readonly line: number; readonly column: number } {
  const before = text.slice(0, offset);
  const line = before.split("\n").length;

  return { line, column: offset - before.lastIndexOf("\n") };
}

/**
 * Parses `text` as TypeScript. A file that does not parse throws a usage error
 * that names `path`, the line and the column, so a codemod never edits a file
 * it cannot read.
 */
export function parseModule(text: string, path: string): ParsedModule {
  const parsed = parseSync(path, text, { sourceType: "module" });
  const [first] = parsed.errors;

  if (first !== undefined) {
    const at = lineColumn(text, first.labels[0]?.start ?? 0);

    throw new CliError(
      "usage",
      `${path}:${at.line}:${at.column}: ${first.message}`,
    );
  }

  return { program: parsed.program, comments: parsed.comments, text };
}

/**
 * Texts read by `parseSource`, newest last. Every doctor rule reads the same
 * sources, so one parse serves all of them. Callers only read the tree; the cap
 * bounds the memory a large app holds.
 */
const PARSED = new Map<string, ParseResult>();
const PARSED_CHARS_MAX = 8_000_000;
let parsedChars = 0;

function remember(text: string, result: ParseResult): void {
  PARSED.set(text, result);
  parsedChars += text.length;

  for (const [oldest] of PARSED) {
    if (parsedChars <= PARSED_CHARS_MAX) {
      break;
    }

    PARSED.delete(oldest);
    parsedChars -= oldest.length;
  }
}

/**
 * Parses source text of unknown flavour. `<T>value` assertions and `<T>(x) =>`
 * generics are only valid in `.ts`, JSX only in `.tsx`, so it reads the text as
 * TypeScript first and as TSX when that reports errors, and keeps the read with
 * fewer errors. A text that parses in neither keeps the recovered tree.
 */
export function parseSource(text: string): ParseResult {
  const known = PARSED.get(text);

  if (known !== undefined) {
    // Re-insert so the entry counts as the newest.
    PARSED.delete(text);
    PARSED.set(text, known);

    return known;
  }

  const typescript = parseSync("source.ts", text, { sourceType: "module" });
  let result = typescript;

  if (typescript.errors.length > 0) {
    const tsx = parseSync("source.tsx", text, { sourceType: "module" });
    result = tsx.errors.length < typescript.errors.length ? tsx : typescript;
  }

  remember(text, result);

  return result;
}
