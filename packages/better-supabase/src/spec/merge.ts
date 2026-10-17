import { isPlainObject } from "../core/clone.ts";

/** Escapes a key for a JSON Pointer (RFC 6901). */
export function pointerToken(key: string): string {
  return key.replaceAll("~", "~0").replaceAll("/", "~1");
}

/**
 * Deep merge: objects merge key by key, anything else (arrays included)
 * is replaced by the patch. `onConflict` hears each replaced leaf whose value
 * differs, with its JSON Pointer. Neither input is changed.
 */
export function mergeJson<T>(
  base: T,
  patch: unknown,
  onConflict?: (pointer: string) => void,
  pointer = "",
): T {
  if (!isPlainObject(base) || !isPlainObject(patch)) {
    if (
      onConflict &&
      base !== undefined &&
      JSON.stringify(base) !== JSON.stringify(patch)
    ) {
      onConflict(pointer);
    }

    // SAFETY: a patch replaces the value at this position; callers merge
    // fragments of the same document shape.
    return patch as T;
  }

  const out: Record<string, unknown> = { ...base };

  for (const [key, value] of Object.entries(patch)) {
    out[key] = Object.hasOwn(base, key)
      ? mergeJson(
          base[key],
          value,
          onConflict,
          `${pointer}/${pointerToken(key)}`,
        )
      : value;
  }

  // SAFETY: the result has every key of the base, merged with the patch.
  return out as T;
}
