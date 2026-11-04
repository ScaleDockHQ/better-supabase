import { isRecord } from "./guards.ts";

/** `value` as JSON with object keys sorted, so key order doesn't matter. */
export function canonicalJson(value: unknown): string {
  return JSON.stringify(value, (_key, each: unknown) =>
    isRecord(each)
      ? Object.fromEntries(
          Object.entries(each).toSorted(([a], [b]) => (a < b ? -1 : 1)),
        )
      : each,
  );
}
