import type { AllowUrl } from "./url-policy.ts";

import { UrlCheckError } from "./safe-fetch.ts";

export interface WebhookRequest {
  readonly url: string;
  readonly headers: Readonly<Record<string, string>>;
  readonly body: string;
  readonly signal?: AbortSignal;
}

export interface WebhookResponse {
  readonly status: number;
  readonly body: string;
  /** Seconds from the `Retry-After` header, when the receiver sent one. */
  readonly retryAfter?: number;
}

/**
 * Sends one signed webhook request. Throw `WebhookPolicyError` when the
 * request must never be retried (a blocked URL); any other error retries.
 */
export interface WebhookTransport {
  readonly apiVersion: 1;
  readonly name: string;
  send(request: WebhookRequest): Promise<WebhookResponse>;
}

/** A delivery that must not be retried, e.g. a URL `allowUrl` rejected. */
export class WebhookPolicyError extends Error {
  override readonly name = "WebhookPolicyError";
}

export interface FetchTransportOptions {
  readonly fetch?: typeof fetch;
  /** Checked before the first request and before each redirect. */
  readonly allowUrl?: AllowUrl;
  /**
   * Defaults to 0: a redirect fails the delivery without a retry. Each hop
   * you allow is checked with `allowUrl` first.
   */
  readonly maxRedirects?: number;
  /** Per request. Defaults to 10 seconds. */
  readonly timeoutMs?: number;
  /** The response body bytes kept; the rest is not read. Defaults to 64 KiB. */
  readonly maxResponseBytes?: number;
}

const REDIRECTS = new Set([301, 302, 303, 307, 308]);

/** `Retry-After` as seconds from now: delta-seconds or an HTTP date. */
export function parseRetryAfter(
  value: string | null,
  now: number = Date.now(),
): number | undefined {
  if (value === null) return undefined;
  const text = value.trim();
  if (/^\d+$/.test(text)) return Number(text);
  const at = Date.parse(text);
  if (Number.isNaN(at)) return undefined;
  return Math.max(0, Math.ceil((at - now) / 1000));
}

/** Reads at most `limit` bytes of the body, then cancels the stream. */
async function readCapped(response: Response, limit: number): Promise<string> {
  if (!response.body) return "";
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let text = "";
  let left = limit;
  try {
    while (left > 0) {
      const { done, value } = await reader.read();
      if (done) return text + decoder.decode();
      const chunk = value.byteLength > left ? value.subarray(0, left) : value;
      left -= chunk.byteLength;
      text += decoder.decode(chunk, { stream: true });
    }
    return text + decoder.decode();
  } finally {
    await reader.cancel().catch(() => undefined);
  }
}

/**
 * A check that threw (a DNS lookup that timed out) is not a refusal: it
 * throws `UrlCheckError`, which the delivery retries.
 */
async function allowed(allowUrl: AllowUrl, url: URL): Promise<boolean> {
  try {
    return await allowUrl(url);
  } catch (cause) {
    throw new UrlCheckError(`Could not check endpoint URL: ${url.host}`, {
      cause,
    });
  }
}

/** Sends webhooks with `fetch`, following redirects only to allowed URLs. */
export function fetchTransport(
  options: FetchTransportOptions = {},
): WebhookTransport {
  const send = options.fetch ?? globalThis.fetch;
  const maxRedirects = options.maxRedirects ?? 0;
  const timeoutMs = options.timeoutMs ?? 10_000;
  const maxResponseBytes = options.maxResponseBytes ?? 65_536;
  return {
    apiVersion: 1,
    name: "fetch",
    async send(request) {
      const timeout = AbortSignal.timeout(timeoutMs);
      const signal = request.signal
        ? AbortSignal.any([request.signal, timeout])
        : timeout;
      let url = new URL(request.url);
      for (let hop = 0; ; hop++) {
        if (options.allowUrl && !(await allowed(options.allowUrl, url)))
          throw new WebhookPolicyError(
            `Endpoint URL is not allowed: ${url.host}`,
          );
        const response = await send(url, {
          method: "POST",
          headers: request.headers,
          body: request.body,
          redirect: "manual",
          signal,
        });
        if (!REDIRECTS.has(response.status)) {
          const retryAfter = parseRetryAfter(
            response.headers.get("retry-after"),
          );
          return {
            status: response.status,
            body: await readCapped(response, maxResponseBytes),
            ...(retryAfter === undefined ? {} : { retryAfter }),
          };
        }
        await response.body?.cancel();
        const location = response.headers.get("location");
        if (!location)
          throw new WebhookPolicyError(
            `Redirect ${String(response.status)} without a location`,
          );
        if (hop >= maxRedirects)
          throw new WebhookPolicyError(
            maxRedirects === 0
              ? `Redirect ${String(response.status)} not followed (maxRedirects is 0)`
              : `More than ${String(maxRedirects)} redirects`,
          );
        url = new URL(location, url);
      }
    },
  };
}
