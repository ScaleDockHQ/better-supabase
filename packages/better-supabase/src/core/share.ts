import { isPlainObject } from "./clone.ts";

function sameValue(prev: unknown, next: unknown): boolean {
  if (Object.is(prev, next)) return true;
  if (typeof prev !== "object" || typeof next !== "object") return false;
  if (prev === null || next === null) return false;
  // Temporal values and dates: equal when their full-precision JSON is.
  return (
    Object.getPrototypeOf(prev) === Object.getPrototypeOf(next) &&
    !Array.isArray(prev) &&
    !isPlainObject(prev) &&
    "toJSON" in prev &&
    typeof prev.toJSON === "function" &&
    JSON.stringify(prev) === JSON.stringify(next)
  );
}

function idOf(value: unknown): unknown {
  return isPlainObject(value) ? value["id"] : undefined;
}

/**
 * `next` with every part that equals `prev` replaced by `prev`'s object, so
 * unchanged rows keep their identity and `memo` skips them. Array items
 * match by their `id` when they have one (a reordered list keeps its rows),
 * else by position. Returns `prev` itself when nothing changed.
 */
export function shareStructure<T>(prev: unknown, next: T): T {
  if (sameValue(prev, next)) {
    // SAFETY: `prev` equals `next`, so it has `next`'s type.
    return prev as T;
  }
  if (Array.isArray(prev) && Array.isArray(next)) {
    const before: readonly unknown[] = prev;
    const after: readonly unknown[] = next;
    const byId = new Map<unknown, unknown>();
    for (const item of before) {
      const id = idOf(item);
      if (id !== undefined) byId.set(id, item);
    }
    let same = before.length === after.length;
    const shared = after.map((item, index) => {
      const id = idOf(item);
      const match = id === undefined ? before[index] : byId.get(id);
      const value = shareStructure(match, item);
      if (value !== before[index]) same = false;
      return value;
    });
    // SAFETY: `shared` holds `next`'s items or equal ones from `prev`.
    return (same ? prev : shared) as T;
  }
  if (isPlainObject(prev) && isPlainObject(next)) {
    const keys = Object.keys(next);
    let same = keys.length === Object.keys(prev).length;
    const shared: Record<string, unknown> = {};
    for (const key of keys) {
      const value = shareStructure(prev[key], next[key]);
      if (!Object.hasOwn(prev, key) || value !== prev[key]) same = false;
      shared[key] = value;
    }
    // SAFETY: `shared` has `next`'s keys with equal values.
    return (same ? prev : shared) as T;
  }
  return next;
}
