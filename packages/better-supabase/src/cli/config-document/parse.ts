import type { Comment, Program } from "oxc-parser";

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
