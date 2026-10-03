import { isPlainObject } from "../ir/build.ts";

/**
 * Copies plain objects and arrays so hooks and listeners cannot change the
 * caller's result (invariant 5). Temporal values are immutable and stay shared.
 */
export function cloneValue(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(cloneValue);
  if (isPlainObject(value)) {
    const copy: Record<string, unknown> = {};
    for (const [key, item] of Object.entries(value))
      copy[key] = cloneValue(item);
    return copy;
  }
  return value;
}
