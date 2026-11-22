import { walk } from "oxc-walker";

import { parseSource } from "./parse.ts";

/**
 * `[start, end)` ranges of code, outside strings, regular expressions, template
 * text, JSX text and comments. A template literal's `${}` expressions are code.
 * The text is read as TSX, and a file that does not parse keeps the ranges of
 * the part the parser recovered.
 */
export function codeRanges(text: string): [number, number][] {
  const parsed = parseSource(text);

  const hidden: [number, number][] = parsed.comments.map((comment) => [
    comment.start,
    comment.end,
  ]);

  walk(parsed.program, {
    enter(node) {
      if (node.type === "TemplateElement" || node.type === "JSXText") {
        hidden.push([node.start, node.end]);
      } else if (node.type === "Literal") {
        const { value } = node;

        if (typeof value === "string" || "regex" in node) {
          hidden.push([node.start, node.end]);
        }
      }
    },
  });

  hidden.sort((a, b) => a[0] - b[0]);

  const ranges: [number, number][] = [];
  let cursor = 0;

  for (const [start, end] of hidden) {
    if (start > cursor) {
      ranges.push([cursor, start]);
    }

    cursor = Math.max(cursor, end);
  }

  if (cursor < text.length) {
    ranges.push([cursor, text.length]);
  }

  return ranges;
}
