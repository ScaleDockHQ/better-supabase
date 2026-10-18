/**
 * The scanner behind the codemods and the config edits: it finds the code
 * between strings, template literals and comments.
 */

/** `[start, end)` ranges of code, outside strings, template literals and comments. */
export function codeRanges(text: string): [number, number][] {
  const ranges: [number, number][] = [];
  let start = 0;
  let index = 0;

  const skip = (end: number): void => {
    if (index > start) {
      ranges.push([start, index]);
    }

    index = end;
    start = end;
  };

  while (index < text.length) {
    const char = text[index]!;
    const next = text[index + 1];

    if (char === "/" && next === "/") {
      const end = text.indexOf("\n", index);
      skip(end === -1 ? text.length : end);
    } else if (char === "/" && next === "*") {
      const end = text.indexOf("*/", index + 2);
      skip(end === -1 ? text.length : end + 2);
    } else if (char === '"' || char === "'" || char === "`") {
      let end = index + 1;

      while (end < text.length && text[end] !== char) {
        if (text[end] === "\\") {
          end += 1;
        }

        if (char !== "`" && text[end] === "\n") {
          break;
        }

        end += 1;
      }

      skip(text[end] === char ? end + 1 : Math.min(end, text.length));
    } else {
      index += 1;
    }
  }

  if (index > start) {
    ranges.push([start, index]);
  }

  return ranges;
}
