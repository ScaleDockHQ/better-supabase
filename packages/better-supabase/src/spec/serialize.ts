import { isPlainObject } from "../core/clone.ts";

export interface SerializeOptions {
  /** Spaces per level. Defaults to 2; 0 writes one line. */
  readonly indent?: number;
  /** Sorts object keys by UTF-16 code unit. Off by default, so generated order stays. */
  readonly sortKeys?: boolean;
}

function normalize(
  value: unknown,
  sortKeys: boolean,
  pointer: string,
): unknown {
  if (typeof value === "number" && !Number.isFinite(value))
    throw new TypeError(
      `better-supabase/spec: ${String(value)} at "${pointer}" has no JSON form`,
    );
  if (Array.isArray(value))
    return value.map((item: unknown, index) =>
      normalize(item, sortKeys, `${pointer}/${index}`),
    );
  if (!isPlainObject(value)) return value;
  const keys = Object.keys(value);
  if (sortKeys) keys.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  const out: Record<string, unknown> = {};
  for (const key of keys) {
    const entry = value[key];
    if (entry === undefined) continue;
    out[key] = normalize(entry, sortKeys, `${pointer}/${key}`);
  }
  return out;
}

/**
 * The document as JSON text: the same document always gives the same
 * bytes, ending in a newline. Throws on `NaN` and infinities, which JSON
 * cannot hold.
 */
export function serializeDocument(
  document: unknown,
  options: SerializeOptions = {},
): string {
  const { indent = 2, sortKeys = false } = options;
  return `${JSON.stringify(normalize(document, sortKeys, ""), null, indent)}\n`;
}

export interface SpecResponseOptions {
  /** Defaults to `public, no-cache`: clients revalidate with the ETag. */
  readonly cacheControl?: string;
  /** Defaults to `application/json`. */
  readonly contentType?: string;
  readonly indent?: number;
}

interface Encoded {
  readonly body: string;
  readonly etag: Promise<string>;
}

const encoded = new WeakMap<object, Map<string, Encoded>>();

function base64url(bytes: ArrayBuffer): string {
  let binary = "";
  for (const byte of new Uint8Array(bytes))
    binary += String.fromCodePoint(byte);
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");
}

function encode(document: object, indent: number): Encoded {
  let byIndent = encoded.get(document);
  if (!byIndent) {
    byIndent = new Map();
    encoded.set(document, byIndent);
  }
  const key = String(indent);
  let hit = byIndent.get(key);
  if (!hit) {
    const body = serializeDocument(document, { indent });
    const etag = crypto.subtle
      .digest("SHA-256", new TextEncoder().encode(body))
      .then((digest) => `"${base64url(digest)}"`);
    hit = { body, etag };
    byIndent.set(key, hit);
  }
  return hit;
}

/** RFC 9110 section 13.1.2: weak comparison, so `W/` prefixes match too. */
function matches(header: string, etag: string): boolean {
  return header
    .split(",")
    .map((tag) => tag.trim().replace(/^W\//, ""))
    .some((tag) => tag === "*" || tag === etag);
}

/**
 * A `Response` that serves a rendered document with a strong ETag (the
 * SHA-256 of the body). A matching `If-None-Match` gets `304`; `HEAD` gets
 * the headers only; other methods than `GET` and `HEAD` get `405`. The body
 * and ETag are computed once per document object.
 */
export async function specResponse(
  document: object,
  request?: Request,
  options: SpecResponseOptions = {},
): Promise<Response> {
  const {
    cacheControl = "public, no-cache",
    contentType = "application/json",
    indent = 2,
  } = options;
  const method = request?.method.toUpperCase() ?? "GET";
  if (method !== "GET" && method !== "HEAD")
    return new Response(null, { status: 405, headers: { allow: "GET, HEAD" } });
  const { body, etag } = encode(document, indent);
  const tag = await etag;
  const headers = {
    "cache-control": cacheControl,
    etag: tag,
  };
  const ifNoneMatch = request?.headers.get("if-none-match");
  if (ifNoneMatch && matches(ifNoneMatch, tag))
    return new Response(null, { status: 304, headers });
  return new Response(method === "HEAD" ? null : body, {
    status: 200,
    headers: { ...headers, "content-type": contentType },
  });
}
