import type { NamingRename } from "./codemod-naming.ts";

import { codeRanges } from "./code-ranges.ts";

/** The innermost unclosed bracket before `at`, counting only code. */
function openBracket(
  text: string,
  at: number,
  ranges: readonly [number, number][],
): "{" | "[" | "(" | undefined {
  const stack: ("{" | "[" | "(")[] = [];

  const push = (char: string): void => {
    if (char === "{" || char === "[" || char === "(") {
      stack.push(char);
    }
  };

  for (const [start, end] of ranges) {
    const stop = Math.min(end, at);

    if (stop <= start) {
      continue;
    }

    for (let index = start; index < stop; index += 1) {
      const char = text[index];

      if (char === "{" || char === "[" || char === "(") {
        push(char);
      } else if (
        (char === "}" || char === "]" || char === ")") &&
        stack.length > 0
      ) {
        stack.pop();
      }
    }

    if (end >= at) {
      break;
    }
  }

  return stack.at(-1);
}

/**
 * `text` with each property or argument name of the `argument` rows renamed: `{
 * workItemId: id }`, `result.workItemId` and the shorthand `{ workItemId }`,
 * which keeps its local name (`{ taskId: workItemId }`). A shorthand whose new
 * name is the same token stays shorthand (`{ taskId }`, not `{ taskId: taskId
 * }`), and so does a key whose value is the new name (`{ workItemId: taskId }`
 * is `{ taskId }`). Only names inside `{` are renamed, plus a member access.
 * The names in an import or export list stay.
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

      const shorthand =
        (previous === "{" || previous === ",") &&
        (after.startsWith(",") || after.startsWith("}"));

      const inObject = openBracket(text, at, ranges) === "{";
      const memberOf = previous === "." && before.at(-2) !== ".";
      const listed = /\b(?:import|export)(?:\s+type)?\s*\{[^}]*$/.test(before);

      let replacement: string | undefined;
      let length = match[0].length;

      if (memberOf) {
        replacement = to;
      } else if (inObject && key && !listed) {
        const same = /^\s*:\s*([A-Za-z_$][\w$]*)(?=\s*[,}])/.exec(
          text.slice(at + length),
        );

        replacement = to;

        if (same?.[1] === to) {
          length += same[0].length;
        }
      } else if (inObject && shorthand && !listed) {
        replacement = to === match[0] ? to : `${to}: ${match[0]}`;
      }

      if (replacement !== undefined) {
        out += text.slice(from, at) + replacement;
        from = at + length;
      }
    }
  }

  return out + text.slice(from);
}

const inCode = (text: string, index: number): boolean =>
  codeRanges(text).some(([first, last]) => index >= first && index < last);

const camel = (name: string): string =>
  name.replaceAll(/-([a-z])/g, (_all, letter: string) => letter.toUpperCase());

const escapeRegExp = (value: string): string =>
  value.replaceAll(/[.*+?^${}()|[\]\\]/g, String.raw`\$&`);

/**
 * `text` with the block keys of the `blocks.<name>` rows renamed where code
 * reads them: `blocks["time-tracking"]`, `blockConfig["time-tracking"]`,
 * `db.$blocks.timeTracking` and the key of a `defineBlocks` entry that reads
 * the block (`"time-tracking": blocks["time-tracking"]`). The config key itself
 * is renamed by the config scanner.
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

    result = result.replaceAll(
      new RegExp(
        String.raw`\b(?:blocks|blockConfig)\s*\[\s*(["'])${escapeRegExp(from)}\1\s*\]`,
        "g",
      ),
      (whole, quote: string, offset: number, source: string) =>
        inCode(source, offset)
          ? `${whole.startsWith("blockConfig") ? "blockConfig" : "blocks"}[${quote}${to}${quote}]`
          : whole,
    );

    result = result.replaceAll(
      new RegExp(
        String.raw`(["'])${escapeRegExp(from)}\1(\s*:\s*blocks\s*\[\s*(["'])${escapeRegExp(to)}\3\s*\])`,
        "g",
      ),
      (
        whole,
        quote: string,
        value: string,
        _inner: string,
        offset: number,
        source: string,
      ) =>
        inCode(source, offset + whole.length - 1)
          ? `${quote}${to}${quote}${value}`
          : whole,
    );

    result = result.replaceAll(
      new RegExp(String.raw`(\$blocks\.)${camel(from)}\b`, "g"),
      (whole, head: string, offset: number, source: string) =>
        inCode(source, offset) ? `${head}${camel(to)}` : whole,
    );
  }

  return result;
}
