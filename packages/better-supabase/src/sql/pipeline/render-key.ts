import type { BlockSqlLayout } from "../module-types.ts";

import { sha256Hex } from "../sha256.ts";

/** Marks a value the key can't cover, so the render runs fresh. */
const UNCACHEABLE: unique symbol = Symbol("uncacheable");

/**
 * `value` as stable JSON text: object keys sorted, maps and sets as tagged
 * arrays. Returns the marker for a function, a symbol or a class instance with
 * state the text can't carry.
 */
function stable(value: unknown): string | typeof UNCACHEABLE {
  if (value === undefined) {
    return "undefined";
  }

  if (value === null || typeof value !== "object") {
    if (typeof value === "function" || typeof value === "symbol") {
      return UNCACHEABLE;
    }

    return JSON.stringify(value);
  }

  if (Array.isArray(value)) {
    return list(value);
  }

  if (value instanceof Map) {
    const inner = list([...value.entries()].toSorted(byKey));

    return inner === UNCACHEABLE ? inner : `map${inner}`;
  }

  if (value instanceof Set) {
    const inner = list([...value]);

    return inner === UNCACHEABLE ? inner : `set${inner}`;
  }

  const proto: unknown = Object.getPrototypeOf(value);

  if (proto !== Object.prototype && proto !== null) {
    return UNCACHEABLE;
  }

  const parts: string[] = [];

  for (const key of Object.keys(value).toSorted()) {
    // SAFETY: `value` is a plain object here (the prototype check above), and `key` comes from its own keys.
    const each = stable((value as Record<string, unknown>)[key]);

    if (each === UNCACHEABLE) {
      return each;
    }

    parts.push(`${JSON.stringify(key)}:${each}`);
  }

  return `{${parts.join(",")}}`;
}

function byKey(a: readonly [unknown, unknown], b: readonly [unknown, unknown]) {
  return String(a[0]).localeCompare(String(b[0]));
}

function list(items: readonly unknown[]): string | typeof UNCACHEABLE {
  const parts: string[] = [];

  for (const item of items) {
    const each = stable(item);

    if (each === UNCACHEABLE) {
      return each;
    }

    parts.push(each);
  }

  return `[${parts.join(",")}]`;
}

/**
 * The cache key of one `renderBlocks` call: the block names, the layout and the
 * generator version. `undefined` when the layout holds a function or other
 * state the key can't cover, which makes the caller render fresh.
 */
export function renderKey(
  names: readonly string[],
  layout: BlockSqlLayout,
  version: string,
): string | undefined {
  const text = stable([version, names, layout]);

  return text === UNCACHEABLE ? undefined : sha256Hex(text);
}

/**
 * The key of any `parts`, with the same rules as `renderKey`: `undefined` when
 * a part holds a function or state the text can't carry.
 */
export function stableKey(parts: unknown): string | undefined {
  const text = stable(parts);

  return text === UNCACHEABLE ? undefined : sha256Hex(text);
}

/**
 * The stable text of `value` (sorted keys, tagged maps and sets), or
 * `undefined` when it holds a function or state the text can't carry.
 */
export function stableText(value: unknown): string | undefined {
  const text = stable(value);

  return text === UNCACHEABLE ? undefined : text;
}
