/** A router or browser prefetch, by its request headers. */
export function isPrefetch(request: Request): boolean {
  const h = request.headers;
  return (
    h.has("next-router-prefetch") ||
    h.get("purpose") === "prefetch" ||
    (h.get("sec-purpose")?.includes("prefetch") ?? false)
  );
}

const FORM_TYPES = ["application/x-www-form-urlencoded", "multipart/form-data"];

/**
 * Whether a request should refresh an expired session cookie: page loads,
 * client navigations (`rsc`, `x-sveltekit-*`, `_data` loaders), form posts
 * and Server Actions. Prefetches, assets and `fetch` calls from scripts
 * read the session as it is, so a burst of parallel requests never races
 * on the single-use refresh token.
 */
export function shouldRefresh(request: Request): boolean {
  const h = request.headers;
  if (request.method !== "GET" && request.method !== "HEAD") {
    if (h.has("next-action") || h.has("x-sveltekit-action")) return true;
    if (h.get("sec-fetch-dest") === "document") return true;
    const type = h.get("content-type") ?? "";
    return FORM_TYPES.some((form) => type.startsWith(form));
  }
  if (isPrefetch(request)) return false;
  if (h.get("rsc") === "1") return true;
  const dest = h.get("sec-fetch-dest");
  if (dest) return dest === "document";
  return h.get("accept")?.includes("text/html") ?? false;
}

/**
 * Whether a request should ask the Auth server if the session still exists
 * (`checkSession`): full page loads, and `paths` you list for client
 * navigations. Never prefetches or mutations.
 */
export function shouldCheckSession(
  request: Request,
  paths?: readonly string[],
): boolean {
  if (request.method !== "GET" && request.method !== "HEAD") return false;
  if (isPrefetch(request)) return false;
  if (request.headers.get("sec-fetch-dest") === "document") return true;
  return paths?.includes(new URL(request.url).pathname) ?? false;
}

/** When a session entry refreshes: always, never, on navigations, or a predicate. */
export type RefreshPolicy =
  | boolean
  | "navigation"
  | ((request: Request) => boolean);

/** `policy` for one request. */
export function refreshFor(
  policy: RefreshPolicy | undefined,
  request: Request,
): boolean | undefined {
  if (policy === undefined || typeof policy === "boolean") return policy;
  return policy === "navigation" ? shouldRefresh(request) : policy(request);
}
