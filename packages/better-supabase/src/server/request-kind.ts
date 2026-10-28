/**
 * A router or browser prefetch, by its request headers: Next.js route and
 * segment prefetches (`next-router-prefetch`, `next-router-segment-prefetch`),
 * Next's middleware prefetch (`x-middleware-prefetch`), and browser and
 * speculation-rules prefetches (`purpose`, `sec-purpose`, `x-moz`).
 *
 * Next.js strips its router headers before `proxy.ts` runs, so there it only
 * sees the browser's; Playwright and server code that reads the original
 * request see them all.
 */
export function isPrefetch(request: Request): boolean {
  const h = request.headers;

  return (
    h.has("next-router-prefetch") ||
    h.has("next-router-segment-prefetch") ||
    h.get("x-middleware-prefetch") === "1" ||
    h.get("purpose") === "prefetch" ||
    h.get("x-moz") === "prefetch" ||
    (h.get("sec-purpose")?.includes("prefetch") ?? false)
  );
}

/**
 * A top-level page load: a `GET` the browser sends with `sec-fetch-dest:
 * document`, else one that accepts HTML and is not an RSC request. Never a
 * prefetch, a client navigation, a `fetch` call or a mutation.
 */
export function isDocumentLoad(request: Request): boolean {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return false;
  }

  if (isPrefetch(request)) {
    return false;
  }

  const h = request.headers;
  const dest = h.get("sec-fetch-dest");

  if (dest) {
    return dest === "document";
  }

  if (h.get("rsc") === "1") {
    return false;
  }

  return h.get("accept")?.includes("text/html") ?? false;
}

/**
 * Whether a request may refresh an expired session: always, never, or a
 * predicate.
 */
export type RefreshPolicy = boolean | ((request: Request) => boolean);

/** `policy` for one request; `undefined` when no policy is set. */
export function refreshFor(
  policy: RefreshPolicy | undefined,
  request: Request,
): boolean | undefined {
  return typeof policy === "function" ? policy(request) : policy;
}
