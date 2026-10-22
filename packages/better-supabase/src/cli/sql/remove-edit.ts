/**
 * The edits `better-supabase remove` makes: blocks out of the config's
 * `blocks`, and their clients out of `lib/blocks.ts`. Textual, like
 * `config-edit.ts`, so comments and formatting survive.
 */

import type { ConfigEdit, Property, WiredBlock } from "./config-edit.ts";

import {
  closingIndex,
  configObject,
  mask,
  properties,
  wiringBlocks,
} from "./config-edit.ts";
import { cutRange, tidyInline } from "./config-group.ts";

/** `source` with `props` whose key is in `keys` cut from the object at `open`. */
function cutKeys(
  source: string,
  open: number,
  props: readonly Property[],
  keys: ReadonlySet<string>,
): string {
  const code = mask(source);
  const multiline = code.slice(open, closingIndex(code, open)).includes("\n");
  let text = source;

  for (let index = props.length - 1; index >= 0; index -= 1) {
    const key = props[index]?.key;

    if (key !== undefined && keys.has(key)) {
      const cut = cutRange(source, code, open, props, index, multiline);
      text = text.slice(0, cut.start) + text.slice(cut.end);
    }
  }

  return multiline ? text : tidyInline(text, open);
}

/** `source` with `names` taken out of `blocks`, keeping the form it has. */
export function removeBlocksFromConfig(
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

  const blocks = properties(source, code, root)?.find(
    (prop) => prop.key === "blocks",
  );

  if (!blocks) {
    return { ok: true, text: source };
  }

  const open = blocks.valueStart;

  if (code[open] === "{") {
    const listed = properties(source, code, open);

    if (!listed) {
      return { ok: false, reason: "its blocks object can't be read" };
    }

    return { ok: true, text: cutKeys(source, open, listed, new Set(names)) };
  }

  if (code[open] === "[") {
    const close = closingIndex(code, open);

    const items = [
      ...source.slice(open + 1, close).matchAll(/(["'])([^"']*)\1/g),
    ];

    const kept = items
      .filter((item) => !names.includes(item[2] ?? ""))
      .map((item) => item[0]);

    if (kept.length === items.length) {
      return { ok: true, text: source };
    }

    return {
      ok: true,
      text: `${source.slice(0, open)}[${kept.join(", ")}]${source.slice(close + 1)}`,
    };
  }

  return { ok: false, reason: "its blocks key isn't a literal object or list" };
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** `removeBlocksFromConfig` for `better-supabase.config.json`. */
export function removeBlocksFromJson(
  source: string,
  names: readonly string[],
): ConfigEdit {
  let config: unknown;

  try {
    config = JSON.parse(source);
  } catch {
    return { ok: false, reason: "it isn't valid JSON" };
  }

  if (!isRecord(config)) {
    return { ok: false, reason: "it isn't a JSON object" };
  }

  const blocks: unknown = config["blocks"];
  let next: unknown;

  if (blocks === undefined) {
    return { ok: true, text: source };
  }

  if (Array.isArray(blocks)) {
    const listed: readonly unknown[] = blocks;
    next = listed.filter(
      (name) => typeof name !== "string" || !names.includes(name),
    );
  } else if (isRecord(blocks)) {
    next = Object.fromEntries(
      Object.entries(blocks).filter(([name]) => !names.includes(name)),
    );
  } else {
    return { ok: false, reason: "its blocks key isn't an object or a list" };
  }

  if (JSON.stringify(next) === JSON.stringify(blocks)) {
    return { ok: true, text: source };
  }

  const indent = /^[ \t]+/m.exec(source)?.[0] ?? "  ";

  return {
    ok: true,
    text: `${JSON.stringify({ ...config, blocks: next }, null, indent)}\n`,
  };
}

/**
 * `lib/blocks.ts` with `blocks` taken out of the blocks object, and the import
 * of each one's export dropped once nothing else names it.
 */
export function removeBlocksFromWiring(
  source: string,
  blocks: readonly WiredBlock[],
): ConfigEdit {
  const found = wiringBlocks(source, mask(source));

  if (!found.ok) {
    return found;
  }

  let text = cutKeys(
    source,
    found.open,
    found.listed,
    new Set(blocks.map((block) => block.key)),
  );

  for (const block of blocks) {
    const line = new RegExp(
      `^import \\{ ${block.export} \\} from ["']${block.subpath.replaceAll("/", "\\/")}["'];\\n`,
      "m",
    );

    const without = text.replace(line, "");
    const named = new RegExp(`\\b${block.export}\\b`);

    if (without !== text && !named.test(mask(without))) {
      text = without;
    }
  }

  return { ok: true, text };
}
