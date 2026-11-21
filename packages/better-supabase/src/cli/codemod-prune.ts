import { codeRanges } from "./code-ranges.ts";
import { closingIndex, listedBlocks, mask } from "./sql/config-edit.ts";

/** Where a property sits in the text, with the object it belongs to. */
interface Located {
  readonly from: number;
  readonly to: number;
  readonly parentOpen: number;
  readonly parentClose: number;
}

const CONFIG_OBJECT = /(?:defineConfig\s*\(\s*|export\s+default\s+)\{/;

/**
 * The indexes of the `{` that opens the config object and the `}` that closes
 * it, or undefined when the file has no `defineConfig({` or `export default
 * {`.
 */
function configObject(
  text: string,
  code: (index: number) => boolean,
): [number, number] | undefined {
  const found = CONFIG_OBJECT.exec(text);

  if (found === null) {
    return undefined;
  }

  const open = found.index + found[0].length - 1;
  const close = matching(text, open, code);

  return close === -1 ? undefined : [open, close];
}

/** The index of the `}` that closes the `{` at `open`, counting code only. */
function matching(
  text: string,
  open: number,
  code: (index: number) => boolean,
): number {
  let depth = 0;

  for (let at = open; at < text.length; at += 1) {
    if (!code(at)) {
      continue;
    }

    if (text[at] === "{") {
      depth += 1;
    } else if (text[at] === "}") {
      depth -= 1;

      if (depth === 0) {
        return at;
      }
    }
  }

  return -1;
}

/** The end of the value that starts at `start`, before its comma or brace. */
function valueEnd(
  text: string,
  start: number,
  limit: number,
  code: (index: number) => boolean,
): number {
  let depth = 0;

  for (let at = start; at < limit; at += 1) {
    if (!code(at)) {
      continue;
    }

    const char = text[at];

    if (char === "{" || char === "[" || char === "(") {
      depth += 1;
    } else if (char === "}" || char === "]" || char === ")") {
      depth -= 1;
    } else if (char === "," && depth === 0) {
      return at;
    }
  }

  return limit;
}

/** The direct property `key` of the object between `open` and `close`. */
function property(
  text: string,
  key: string,
  open: number,
  close: number,
  code: (index: number) => boolean,
): Located | undefined {
  const pattern = new RegExp(
    String.raw`(?:"${key}"|'${key}'|(?<![\w$.])${key})\s*:\s*`,
    "g",
  );

  const body = text.slice(open + 1, close);
  let depth = 0;
  const depths: number[] = [];

  for (let at = 0; at < body.length; at += 1) {
    depths.push(depth);

    if (code(open + 1 + at)) {
      if (body[at] === "{" || body[at] === "[" || body[at] === "(") {
        depth += 1;
      } else if (body[at] === "}" || body[at] === "]" || body[at] === ")") {
        depth -= 1;
      }
    }
  }

  for (const found of body.matchAll(pattern)) {
    const at = found.index;
    const quoted = found[0].startsWith('"') || found[0].startsWith("'");
    let back = at - 1;

    // Skip whitespace and comments: the key follows a `{` or `,` in code.
    while (back >= 0 && (/\s/.test(body[back]!) || !code(open + 1 + back))) {
      back -= 1;
    }

    const before = back < 0 ? "" : body[back]!;

    if (
      depths[at] !== 0 ||
      (!quoted && !code(open + 1 + at)) ||
      (before !== "" && before !== "{" && before !== ",")
    ) {
      continue;
    }

    const start = open + 1 + at;
    const valueStart = start + found[0].length;
    const end = valueEnd(text, valueStart, close, code);

    return { from: start, to: end, parentOpen: open, parentClose: close };
  }

  return undefined;
}

/**
 * The properties along `path`, outermost first, or undefined when one is
 * missing. In a `blocks` list the entry `blocks.<name>` is the list element,
 * and a name with no config has nothing below it.
 */
function locate(text: string, path: readonly string[]): Located[] | undefined {
  const ranges = codeRanges(text);

  const code = (index: number): boolean =>
    ranges.some(([start, end]) => index >= start && index < end);

  let scope = configObject(text, code);

  if (scope === undefined) {
    return undefined;
  }

  const chain: Located[] = [];

  for (let index = 0; index < path.length; index += 1) {
    const found = property(text, path[index]!, scope[0], scope[1], code);

    if (found === undefined) {
      return undefined;
    }

    chain.push(found);

    if (index === path.length - 1) {
      break;
    }

    const colon = text.indexOf(":", found.from) + 1;
    const next = text.slice(colon).search(/\S/);
    const open = colon + next;

    if (next !== -1 && text[open] === "[" && index === 0) {
      const masked = mask(text);
      const close = closingIndex(masked, open);

      const element = listedBlocks(text, masked, open).find(
        (item) => item.name === path[index + 1],
      );

      if (element?.open === undefined) {
        return undefined;
      }

      chain.push({
        from: element.span.start,
        to: element.span.end,
        parentOpen: open,
        parentClose: close,
      });

      scope = [element.open, closingIndex(masked, element.open)];
      index += 1;

      continue;
    }

    if (next === -1 || text[open] !== "{") {
      return undefined;
    }

    const close = matching(text, open, code);

    if (close === -1) {
      return undefined;
    }

    scope = [open, close];
  }

  return chain;
}

/** `text` without the property at `path`, or undefined when it isn't found. */
function withoutPath(
  text: string,
  path: readonly string[],
): string | undefined {
  const chain = locate(text, path);

  if (chain === undefined) {
    return undefined;
  }

  // Remove the deepest property, then each parent it leaves empty, down to the
  // block's own entry (`blocks.<name>` stays: it installs the block).
  let out = text;
  let level = chain.length - 1;
  let target = chain[level]!;

  for (;;) {
    out = removeRange(out, target.from, target.to);

    const open = target.parentOpen;
    const close = matchingAfter(out, open, target);

    if (
      level <= 2 ||
      out.slice(open + 1, close).replaceAll(/[\s,]/g, "") !== ""
    ) {
      return out;
    }

    level -= 1;

    // Positions after the removed range shift; locate the parent again.
    const reparsed = locate(out, path.slice(0, level + 1))?.at(-1);

    if (reparsed === undefined) {
      return out;
    }

    target = reparsed;
  }
}

function matchingAfter(text: string, open: number, removed: Located): number {
  const ranges = codeRanges(text);

  const code = (index: number): boolean =>
    ranges.some(([start, end]) => index >= start && index < end);

  const close = matching(text, open, code);

  return close === -1 ? removed.parentClose : close;
}

/** `text` without `[from, to)`, its comma and the whole line when it is alone. */
function removeRange(text: string, from: number, to: number): string {
  let start = from;
  let end = to;

  if (text[end] === ",") {
    end += 1;
  }

  const lineStart = text.lastIndexOf("\n", start - 1) + 1;
  const lineEnd = text.indexOf("\n", end);
  const before = text.slice(lineStart, start);
  const after = text.slice(end, lineEnd === -1 ? text.length : lineEnd);

  if (before.trim() === "" && after.trim() === "") {
    start = lineStart;
    end = lineEnd === -1 ? text.length : lineEnd + 1;
  } else if (text[to] !== ",") {
    // The last property: take the comma before it instead.
    const comma = text.slice(0, from).trimEnd();

    if (comma.endsWith(",")) {
      start = comma.length - 1;
    }
  }

  return text.slice(0, start) + text.slice(end);
}

/**
 * `text` without the config entries at `paths`, each as `blocks.<name>...`, and
 * the paths it could not find.
 */
export function withoutConfigPaths(
  text: string,
  paths: readonly string[],
): { readonly text: string; readonly missed: readonly string[] } {
  let out = text;
  const missed: string[] = [];

  for (const path of paths) {
    const next = withoutPath(out, path.split("."));

    if (next === undefined) {
      missed.push(path);
    } else {
      out = next;
    }
  }

  return { text: out, missed };
}

/**
 * The value of the config's top-level property `key`: where its text starts and
 * ends, or undefined when the file has no config object or no such key.
 */
export function topLevelValue(
  text: string,
  key: string,
): { readonly start: number; readonly end: number } | undefined {
  const ranges = codeRanges(text);

  const code = (index: number): boolean =>
    ranges.some(([start, end]) => index >= start && index < end);

  const scope = configObject(text, code);

  if (scope === undefined) {
    return undefined;
  }

  const found = property(text, key, scope[0], scope[1], code);

  if (found === undefined) {
    return undefined;
  }

  const colon = text.indexOf(":", found.from);

  return { start: colon + 1, end: found.to };
}
