import { base64ToText, toBase64Url } from "./base64.ts";
import { isList } from "./guards.ts";

interface BoundCursor {
  /** The hash of the sort the cursor was made for (`sortKey`). */
  readonly s: string;
  readonly v: unknown[];
}

function isBound(value: unknown): value is BoundCursor {
  return (
    typeof value === "object" &&
    value !== null &&
    "s" in value &&
    typeof value.s === "string" &&
    "v" in value &&
    Array.isArray(value.v)
  );
}

function parse(cursor: string): unknown {
  try {
    return JSON.parse(base64ToText(cursor));
  } catch {
    return undefined;
  }
}

/** Opaque, URL-safe keyset cursor. */
export function encodeCursor(values: readonly unknown[]): string {
  return toBase64Url(JSON.stringify(values));
}

/** The values of a cursor from `encodeCursor` or from `paginate()`. */
export function decodeCursor(cursor: string): unknown[] | undefined {
  const parsed = parse(cursor);
  if (isList(parsed)) return [...parsed];
  return isBound(parsed) ? parsed.v : undefined;
}

/** A short FNV-1a hash of `text`, enough to tell two sorts apart. */
export function sortKey(text: string): string {
  let hash = 0x811c9dc5;
  for (let index = 0; index < text.length; index++) {
    hash ^= text.codePointAt(index) ?? 0;
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(36);
}

/** A `paginate()` cursor that only continues the sort `key` names. */
export function encodeBoundCursor(
  values: readonly unknown[],
  key: string,
): string {
  return toBase64Url(JSON.stringify({ s: key, v: values }));
}

/**
 * The values of a `paginate()` cursor made for the sort `key`. `sort` means
 * the cursor is valid but continues another sort or table.
 */
export function decodeBoundCursor(
  cursor: string,
  key: string,
): { readonly values: unknown[] } | { readonly invalid: "cursor" | "sort" } {
  const parsed = parse(cursor);
  if (!isBound(parsed)) return { invalid: "cursor" };
  return parsed.s === key ? { values: parsed.v } : { invalid: "sort" };
}
