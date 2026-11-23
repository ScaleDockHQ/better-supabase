import type { Program } from "oxc-parser";

import { MagicString } from "magic-string";

import type { ReviewLine } from "../codemod.ts";

import { lineColumn, parseSource } from "./parse.ts";

/** What a source rewrite callback gets: the tree, the text and a splicer. */
export interface SourceContext {
  readonly program: Program;
  readonly text: string;
  readonly edit: MagicString;
  /**
   * Adds a review line for the code at `offset`, which the rewrite could not
   * follow.
   */
  readonly report: (offset: number, message: string) => void;
}

/**
 * Rewrites a source file (TypeScript or TSX) through `callback` and returns the
 * new text with the review lines it reported. A file that does not parse comes
 * back unchanged with one review line that names the position, so the file is
 * listed instead of skipped. Line endings stay as written: the callback splices
 * ranges and never rebuilds the text.
 */
export function rewriteSource(
  text: string,
  callback: (context: SourceContext) => void,
): { readonly text: string; readonly review: readonly ReviewLine[] } {
  const parsed = parseSource(text);
  const review: ReviewLine[] = [];

  const [first] = parsed.errors;

  if (first !== undefined) {
    const at = lineColumn(text, first.labels[0]?.start ?? 0);

    return {
      text,
      review: [
        {
          line: at.line,
          message: `the file does not parse (${first.message}), so the codemod left it unchanged; fix it and run the codemod again.`,
        },
      ],
    };
  }

  const edit = new MagicString(text);

  callback({
    program: parsed.program,
    text,
    edit,
    report: (offset, message) => {
      review.push({ line: lineColumn(text, offset).line, message });
    },
  });

  return { text: edit.hasChanged() ? edit.toString() : text, review };
}
