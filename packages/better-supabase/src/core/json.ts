import { isRecord } from "./guards.ts";

/**
 * A `JSON.stringify` replacer: `bigint` values become decimal strings, as the
 * wire codec writes them.
 */
export function jsonReplacer(_key: string, value: unknown): unknown {
  return typeof value === "bigint" ? value.toString() : value;
}

/**
 * `Response.json` that writes `bigint` values as decimal strings instead of
 * throwing.
 */
export function jsonResponse(data: unknown, init: ResponseInit = {}): Response {
  const headers = new Headers(init.headers);

  if (!headers.has("content-type")) {
    headers.set("content-type", "application/json");
  }

  return new Response(JSON.stringify(data, jsonReplacer), { ...init, headers });
}

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
