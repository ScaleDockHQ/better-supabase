import {
  type AllowUrl,
  publicUrl,
  type PublicUrlOptions,
} from "./url-policy.ts";

export interface SafeFetchOptions extends PublicUrlOptions {
  /** The fetch to call. Defaults to the global `fetch`. */
  readonly fetch?: typeof fetch;
  /**
   * Decides which URLs a request (and each redirect) may reach. Defaults to
   * `publicUrl(options)`: HTTPS only, no credentials, public addresses only.
   */
  readonly allowUrl?: AllowUrl;
  /** Redirects followed, each checked with `allowUrl`. Defaults to 3. */
  readonly maxRedirects?: number;
  /** Per call, across redirects. Defaults to 10 seconds. */
  readonly timeoutMs?: number;
  readonly sensitiveHeaders?: readonly string[];
}

/** A request `safeFetch` refused: a URL outside the policy or too many redirects. */
export class UnsafeUrlError extends Error {
  override readonly name = "UnsafeUrlError";
}

const REDIRECTS = new Set([301, 302, 303, 307, 308]);

/**
 * Whether a redirect keeps the method and body, as fetch does: 307 and 308
 * always, 301 and 302 except for POST, 303 only for HEAD.
 */
const keepsMethod = (status: number, method: string): boolean =>
  status === 307 ||
  status === 308 ||
  ((status === 301 || status === 302) && method !== "POST") ||
  (status === 303 && method === "HEAD");

/** Headers a redirect to another origin drops, as fetch does. */
const CREDENTIALS = ["authorization", "cookie", "proxy-authorization"];

/**
 * A `fetch` for URLs that users or tenants supply (link previews, imports,
 * avatars by URL, callback URLs): it refuses private, loopback and
 * link-local addresses, non-HTTPS URLs and credentials in the URL, checks
 * every redirect against the same policy before following it, and stops
 * after `timeoutMs`. It throws `UnsafeUrlError` for a refused URL. A redirect
 * to another origin drops the credential headers and `sensitiveHeaders`.
 *
 * DNS can change between the check and the connection; route the requests
 * through an egress proxy when that matters.
 */
export function createSafeFetch(options: SafeFetchOptions = {}): typeof fetch {
  const send = options.fetch ?? globalThis.fetch;
  const allowUrl = options.allowUrl ?? publicUrl(options);
  const maxRedirects = options.maxRedirects ?? 3;
  const timeoutMs = options.timeoutMs ?? 10_000;
  const sensitive = [...CREDENTIALS, ...(options.sensitiveHeaders ?? [])];
  const check = async (url: URL): Promise<void> => {
    let ok = false;
    try {
      ok = await allowUrl(url);
    } catch {
      ok = false;
    }
    if (!ok) throw new UnsafeUrlError(`URL is not allowed: ${url.host}`);
  };
  return async (input, init) => {
    await check(new URL(input instanceof Request ? input.url : String(input)));
    const request = new Request(input, init);
    const timeout = AbortSignal.timeout(timeoutMs);
    const signal = AbortSignal.any([request.signal, timeout]);
    let url = new URL(request.url);
    let method = request.method;
    const headers = new Headers(request.headers);
    let body: ArrayBuffer | undefined =
      method === "GET" || method === "HEAD"
        ? undefined
        : await request.arrayBuffer();
    for (let hop = 0; ; hop++) {
      if (hop > 0) await check(url);
      const response = await send(url, {
        method,
        headers,
        ...(body === undefined ? {} : { body }),
        redirect: "manual",
        signal,
      });
      if (!REDIRECTS.has(response.status)) return response;
      await response.body?.cancel();
      const location = response.headers.get("location");
      if (!location || hop >= maxRedirects) {
        throw new UnsafeUrlError(
          location
            ? `More than ${String(maxRedirects)} redirects`
            : `Redirect ${String(response.status)} without a location`,
        );
      }
      if (!keepsMethod(response.status, method)) {
        method = "GET";
        body = undefined;
      }
      const next = new URL(location, url);
      if (next.origin !== url.origin) {
        for (const name of sensitive) headers.delete(name);
      }
      url = next;
    }
  };
}
