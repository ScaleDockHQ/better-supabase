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

const camel = (name: string): string =>
  name.replaceAll(/-([a-z])/g, (_all, letter: string) => letter.toUpperCase());

const escapeRegExp = (value: string): string =>
  value.replaceAll(/[.*+?^${}()|[\]\\]/g, String.raw`\$&`);

/**
 * `text` with the block keys of the `blocks.<name>` rows renamed where code
 * reads them: `blocks["time-tracking"]` and `db.$blocks.timeTracking`. The
 * config key itself is renamed by the config scanner.
 */
export function renameBlockReferences(
  text: string,
  renames: readonly NamingRename[],
): string {
  let result = text;

  for (const rename of renames) {
    const from = /^blocks\.([^.]+)$/.exec(rename.from)?.[1];
    const to = /^blocks\.([^.]+)$/.exec(rename.to)?.[1];

    if (rename.kind !== "configKey" || from === undefined || to === undefined) {
      continue;
    }

    const ranges = codeRanges(result);

    const inCode = (index: number): boolean =>
      ranges.some(([start, end]) => index >= start && index < end);

    result = result
      .replaceAll(
        new RegExp(
          String.raw`\bblocks\s*\[\s*(["'])${escapeRegExp(from)}\1\s*\]`,
          "g",
        ),
        (whole, quote: string, offset: number) =>
          inCode(offset) ? `blocks[${quote}${to}${quote}]` : whole,
      )
      .replaceAll(
        new RegExp(String.raw`(\$blocks\.)${camel(from)}\b`, "g"),
        (whole, head: string, offset: number) =>
          inCode(offset) ? `${head}${camel(to)}` : whole,
      );
  }

  return result;
}
