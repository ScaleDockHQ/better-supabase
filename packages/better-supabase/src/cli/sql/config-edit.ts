/**
 * Adds block names to `blocks` in `better-supabase.config.ts`. The
 * edit reads the object literal passed to `defineConfig(...)` (or the
 * default export) with the codemod scanner, so strings and comments never
 * count as code, and inserts the names in the form the config already uses:
 * `name: {}` in an object, `"name"` in a list. Anything that isn't a literal
 * object it can follow is refused with a reason, and `sql add` prints the
 * snippet instead.
 */

import { codeRanges } from "../codemod.ts";

export type ConfigEdit =
  | { readonly ok: true; readonly text: string }
  | { readonly ok: false; readonly reason: string };

interface Property {
  /** The key, unquoted; undefined for a spread or a computed key. */
  readonly key: string | undefined;
  readonly start: number;
  readonly valueStart: number;
  /** The index after the value, before any comma. */
  readonly valueEnd: number;
}

const OPENING = "({[";
const CLOSING = ")}]";
const IDENT = /^[A-Za-z_$][\w$]*$/;

/**
 * `source` with every character outside code replaced: string and template
 * contents become `x` between their quotes, comments become spaces. Indexes
 * stay the same, so a match in the mask is a position in `source`.
 */
function mask(source: string): string {
  const ranges = codeRanges(source);
  let out = "";
  let cursor = 0;
  const hide = (end: number): void => {
    const gap = source.slice(cursor, end);
    const quote = gap[0];
    if (quote === '"' || quote === "'" || quote === "`") {
      const closed = gap.length > 1 && gap.endsWith(quote);
      const inner = gap.slice(1, closed ? -1 : undefined);
      out += quote + inner.replaceAll(/[^\n]/g, "x") + (closed ? quote : "");
    } else {
      out += gap.replaceAll(/[^\n]/g, " ");
    }
  };
  for (const [start, end] of ranges) {
    if (start > cursor) hide(start);
    out += source.slice(start, end);
    cursor = end;
  }
  if (cursor < source.length) hide(source.length);
  return out;
}

/** The index of the bracket that closes the one at `open`. */
function closingIndex(code: string, open: number): number {
  let depth = 0;
  for (let index = open; index < code.length; index += 1) {
    const char = code[index]!;
    if (char === '"' || char === "'" || char === "`") {
      index = code.indexOf(char, index + 1);
      if (index === -1) return -1;
    } else if (OPENING.includes(char)) depth += 1;
    else if (CLOSING.includes(char)) {
      depth -= 1;
      if (depth === 0) return index;
    }
  }
  return -1;
}

const skipSpace = (code: string, index: number): number => {
  while (index < code.length && /\s/.test(code[index]!)) index += 1;
  return index;
};

/** The end of the expression starting at `index`: the next `,` or closer at depth 0. */
function valueEnd(code: string, index: number): number {
  let depth = 0;
  let end = index;
  for (; end < code.length; end += 1) {
    const char = code[end]!;
    if (char === '"' || char === "'" || char === "`") {
      end = code.indexOf(char, end + 1);
      if (end === -1) return code.length;
    } else if (OPENING.includes(char)) depth += 1;
    else if (CLOSING.includes(char)) {
      if (depth === 0) break;
      depth -= 1;
    } else if (char === "," && depth === 0) break;
  }
  while (end > index && /\s/.test(code[end - 1]!)) end -= 1;
  return end;
}

/** The properties of the object literal whose `{` is at `open`. */
function properties(
  source: string,
  code: string,
  open: number,
): readonly Property[] | undefined {
  const close = closingIndex(code, open);
  if (close === -1) return undefined;
  const found: Property[] = [];
  let index = skipSpace(code, open + 1);
  while (index < close) {
    const start = index;
    let key: string | undefined;
    if (code.startsWith("...", index)) {
      index += 3;
    } else if (code[index] === '"' || code[index] === "'") {
      const end = code.indexOf(code[index]!, index + 1);
      key = source.slice(index + 1, end);
      index = end + 1;
    } else if (code[index] === "[") {
      index = closingIndex(code, index) + 1;
    } else {
      const name = /^[A-Za-z_$][\w$]*/.exec(code.slice(index))?.[0];
      if (!name) return undefined;
      key = name;
      index += name.length;
    }
    index = skipSpace(code, index);
    let valueStart = index;
    if (key !== undefined && code[index] === ":") {
      valueStart = skipSpace(code, index + 1);
    } else if (code[index] === "(") {
      // A method: its value runs through the body.
      valueStart = start;
    } else if (key !== undefined && (code[index] === "," || index === close)) {
      valueStart = start;
    }
    const end = valueEnd(code, valueStart);
    found.push({ key, start, valueStart, valueEnd: end });
    index = skipSpace(code, end);
    if (code[index] === ",") index = skipSpace(code, index + 1);
    else if (index !== close) return undefined;
  }
  return found;
}

/** The `{` of the config object: `defineConfig({...})` or `export default {...}`. */
function configObject(code: string): number | undefined {
  const call = /\bdefineConfig\s*(?:<[^>]*>)?\s*\(\s*\{/.exec(code);
  if (call) return call.index + call[0].length - 1;
  const literal =
    /\bexport\s+default\s*\{/.exec(code) ??
    /\bmodule\.exports\s*=\s*\{/.exec(code);
  return literal ? literal.index + literal[0].length - 1 : undefined;
}

const indentAt = (source: string, index: number): string =>
  /^[ \t]*/.exec(source.slice(source.lastIndexOf("\n", index - 1) + 1))?.[0] ??
  "";

/** A module name as an object key, quoted when it isn't an identifier. */
export const keyText = (name: string): string =>
  IDENT.test(name) ? name : `"${name}"`;

interface Span {
  readonly start: number;
  readonly end: number;
}

/** The elements of the array literal whose `[` is at `open`. */
function elements(code: string, open: number): readonly Span[] {
  const close = closingIndex(code, open);
  const found: Span[] = [];
  let index = skipSpace(code, open + 1);
  while (index < close) {
    const end = valueEnd(code, index);
    found.push({ start: index, end });
    index = skipSpace(code, end);
    if (code[index] !== ",") break;
    index = skipSpace(code, index + 1);
  }
  return found;
}

/**
 * The edit that appends `entries` to the object or array whose opener is at
 * `open`, after `last`, its last entry. It follows the literal's layout: one
 * entry per line when it spans lines, inline otherwise, and a trailing comma
 * when the last entry has one.
 */
function append(
  source: string,
  code: string,
  open: number,
  last: Span | undefined,
  entries: readonly string[],
): { readonly start: number; readonly end: number; readonly text: string } {
  const close = closingIndex(code, open);
  const multiline = code.slice(open, close).includes("\n");
  if (last === undefined) {
    if (!multiline) {
      const inner = entries.join(", ");
      return {
        start: open + 1,
        end: close,
        text: code[open] === "{" ? ` ${inner} ` : inner,
      };
    }
    const indent = `${indentAt(source, open)}  `;
    return {
      start: open + 1,
      end: close,
      text: `\n${entries.map((entry) => `${indent}${entry},`).join("\n")}\n${indentAt(source, close)}`,
    };
  }
  if (!multiline) {
    return {
      start: last.end,
      end: last.end,
      text: entries.map((entry) => `, ${entry}`).join(""),
    };
  }
  const indent = indentAt(source, last.start);
  const after = skipSpace(code, last.end);
  if (code[after] === ",") {
    return {
      start: after + 1,
      end: after + 1,
      text: entries.map((entry) => `\n${indent}${entry},`).join(""),
    };
  }
  return {
    start: last.end,
    end: last.end,
    text: entries.map((entry) => `,\n${indent}${entry}`).join(""),
  };
}

const lastOf = (props: readonly Property[]): Span | undefined => {
  const last = props.at(-1);
  return last ? { start: last.start, end: last.valueEnd } : undefined;
};

/** `source` with `names` added to `blocks`, keeping the form it has. */
export function addBlocksToConfig(
  source: string,
  names: readonly string[],
): ConfigEdit {
  const code = mask(source);
  const root = configObject(code);
  if (root === undefined) {
    return {
      ok: false,
      reason: "it doesn't pass an object literal to defineConfig()",
    };
  }
  const rootProps = properties(source, code, root);
  if (!rootProps)
    return { ok: false, reason: "its config object can't be read" };
  const blocks = rootProps.find((prop) => prop.key === "blocks");
  const edit = (start: number, end: number, text: string): ConfigEdit => ({
    ok: true,
    text: source.slice(0, start) + text + source.slice(end),
  });
  if (!blocks) {
    const entries = names.map((name) => `${keyText(name)}: {}`).join(", ");
    const change = append(source, code, root, lastOf(rootProps), [
      `blocks: { ${entries} }`,
    ]);
    return edit(change.start, change.end, change.text);
  }
  const open = blocks.valueStart;
  if (code[open] === "{") {
    const listed = properties(source, code, open);
    if (!listed)
      return { ok: false, reason: "its blocks object can't be read" };
    const keys = new Set(listed.map((prop) => prop.key));
    const missing = names.filter((name) => !keys.has(name));
    if (missing.length === 0) return { ok: true, text: source };
    const change = append(
      source,
      code,
      open,
      lastOf(listed),
      missing.map((name) => `${keyText(name)}: {}`),
    );
    return edit(change.start, change.end, change.text);
  }
  if (code[open] === "[") {
    const items = [
      ...source
        .slice(open + 1, closingIndex(code, open))
        .matchAll(/(["'])([^"']*)\1/g),
    ];
    const quote = items[0]?.[1] ?? '"';
    const present = new Set(items.map((item) => item[2]));
    const missing = names.filter((name) => !present.has(name));
    if (missing.length === 0) return { ok: true, text: source };
    const last = elements(code, open).at(-1);
    const change = append(
      source,
      code,
      open,
      last,
      missing.map((name) => `${quote}${name}${quote}`),
    );
    return edit(change.start, change.end, change.text);
  }
  return { ok: false, reason: "its blocks key isn't a literal object or list" };
}

/** `addBlocksToConfig` for `better-supabase.config.json`. */
export function addBlocksToJson(
  source: string,
  names: readonly string[],
): ConfigEdit {
  let config: unknown;
  try {
    config = JSON.parse(source);
  } catch {
    return { ok: false, reason: "it isn't valid JSON" };
  }
  if (!isObject(config)) return { ok: false, reason: "it isn't a JSON object" };
  const blocks: unknown = config["blocks"] ?? {};
  let next: unknown;
  if (Array.isArray(blocks)) {
    const listed: readonly unknown[] = blocks;
    next = [...listed, ...names.filter((name) => !listed.includes(name))];
  } else if (isObject(blocks)) {
    next = {
      ...blocks,
      ...Object.fromEntries(
        names.filter((name) => !(name in blocks)).map((name) => [name, {}]),
      ),
    };
  } else {
    return { ok: false, reason: "its blocks key isn't an object or a list" };
  }
  const indent = /^[ \t]+/m.exec(source)?.[0] ?? "  ";
  return {
    ok: true,
    text: `${JSON.stringify({ ...config, blocks: next }, null, indent)}\n`,
  };
}

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);
