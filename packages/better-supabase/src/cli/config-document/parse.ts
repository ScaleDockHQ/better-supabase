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
 * Parses source text of unknown flavour. `<T>value` assertions and `<T>(x) =>`
 * generics are only valid in `.ts`, JSX only in `.tsx`, so it reads the text as
 * TypeScript first and as TSX when that reports errors, and keeps the read with
 * fewer errors. A text that parses in neither keeps the recovered tree.
 */
export function parseSource(text: string): ParseResult {
  const typescript = parseSync("source.ts", text, { sourceType: "module" });

  if (typescript.errors.length === 0) {
    return typescript;
  }

  const tsx = parseSync("source.tsx", text, { sourceType: "module" });

  return tsx.errors.length < typescript.errors.length ? tsx : typescript;
}
