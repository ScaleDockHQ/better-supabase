import type { ReviewHint, ReviewLine } from "./codemod.ts";

/** One review line per line of `text` that a hint's pattern matches. */
export function linesMatching(
  text: string,
  hints: readonly ReviewHint[],
): ReviewLine[] {
  return hints.flatMap((hint) =>
    text
      .split("\n")
      .flatMap((line, index) =>
        hint.pattern.test(line)
          ? [{ line: index + 1, message: hint.message }]
          : [],
      ),
  );
}
