import type { NamingRename } from "./codemod-naming.ts";

import { codeRanges } from "./code-ranges.ts";

/**
 * `text` with each property or argument name of the `argument` rows renamed: `{
 * workItemId: id }`, `result.workItemId` and the shorthand `{ workItemId }`,
 * which keeps its local name (`{ taskId: workItemId }`). Only code counts, and
 * the names in an import or export list stay.
 */
export function renameArguments(
  text: string,
  renames: readonly NamingRename[],
): string {
  const names = new Map(
    renames
      .filter((rename) => rename.kind === "argument")
      .map((rename) => [rename.from, rename.to]),
  );

  if (names.size === 0) {
    return text;
  }

  const ranges = codeRanges(text);
  let out = "";
  let from = 0;

  for (const [start, end] of ranges) {
    for (const match of text.slice(start, end).matchAll(/[A-Za-z_$][\w$]*/g)) {
      const to = names.get(match[0]);

      if (to === undefined) {
        continue;
      }

      const at = start + match.index;
      const before = text.slice(0, at).trimEnd();
      const after = text.slice(at + match[0].length).trimStart();
      const previous = before.at(-1);
      const key = after.startsWith(":") && !after.startsWith("::");
      const shorthand = after.startsWith(",") || after.startsWith("}");

      const insideBraces =
        previous === "{" || previous === "," || previous === undefined;

      const memberOf = previous === "." && before.at(-2) !== ".";

      const listed = /\b(?:import|export)(?:\s+type)?\s*\{[^}]*$/.test(before);

      let replacement: string | undefined;

      if (memberOf) {
        replacement = to;
      } else if (insideBraces && key && !listed) {
        replacement = to;
      } else if (insideBraces && shorthand && !listed) {
        replacement = `${to}: ${match[0]}`;
      }

      if (replacement !== undefined) {
        out += text.slice(from, at) + replacement;
        from = at + match[0].length;
      }
    }
  }

  return out + text.slice(from);
}
