/** A `JSON.stringify` replacer: `bigint` values become decimal strings, as the wire codec writes them. */
export function jsonReplacer(_key: string, value: unknown): unknown {
  return typeof value === "bigint" ? value.toString() : value;
}

/** `Response.json` that writes `bigint` values as decimal strings instead of throwing. */
export function jsonResponse(data: unknown, init: ResponseInit = {}): Response {
  const headers = new Headers(init.headers);
  if (!headers.has("content-type"))
    headers.set("content-type", "application/json");
  return new Response(JSON.stringify(data, jsonReplacer), {
    ...init,
    headers,
  });
}
