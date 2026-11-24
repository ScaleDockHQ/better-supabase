import { isRecord } from "./guards.ts";

function keysSorted(record: Record<string, unknown>): boolean {
  let previous: string | undefined;

  for (const key of Object.keys(record)) {
    if (previous !== undefined && key < previous) {
      return false;
    }

    previous = key;
  }

  return true;
}

/** `value` as JSON with object keys sorted, so key order doesn't matter. */
export function canonicalJson(value: unknown): string {
  return JSON.stringify(value, (_key, each: unknown) => {
    if (!isRecord(each)) {
      return each;
    }

    return keysSorted(each)
      ? each
      : Object.fromEntries(
          Object.entries(each).toSorted(([a], [b]) => (a < b ? -1 : 1)),
        );
  });
}
