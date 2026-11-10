/** One finished outbound request, as `observedFetch` reports it. */
export interface ObservedFetchCall {
  /** The request's method, upper case. */
  readonly method: string;
  /** Origin and path of the request, without the query string. */
  readonly url: string;
  /** The response status, or `undefined` when the request threw. */
  readonly status: number | undefined;
  /** Milliseconds from the call to the response headers (or the failure). */
  readonly durationMs: number;
  /** The error name when the request threw (`AbortError`, `TypeError`). */
  readonly error?: string;
}

export interface ObservedFetchOptions {
  /** Called once per request, after it settled. A throwing observer is ignored. */
  readonly onCall: (call: ObservedFetchCall) => void;
  /** The fetch to wrap. Defaults to `globalThis.fetch`. */
  readonly fetch?: typeof globalThis.fetch;
  /** The clock. Defaults to `performance.now`. */
  readonly now?: () => number;
}

/** Method and URL without the query string, which can carry tokens. */
function describe(
  input: Parameters<typeof fetch>[0],
  init: Parameters<typeof fetch>[1],
): { method: string; url: string } {
  const request =
    typeof input === "object" && "url" in input ? input : undefined;

  const raw = request ? request.url : String(input);

  const method = (init?.method ?? request?.method ?? "GET").toUpperCase();

  try {
    const parsed = new URL(raw);

    return { method, url: `${parsed.origin}${parsed.pathname}` };
  } catch {
    return { method, url: raw.split("?")[0] ?? raw };
  }
}

/**
 * Wraps `fetch` so every request reports its method, URL, status and duration
 * to `onCall`, for example to count the Data API calls of one request or to
 * trace them. The response is returned untouched and the observer can never
 * change or fail a request. Pass it as `createServer({ fetch })`.
 */
export function observedFetch(
  options: ObservedFetchOptions,
): typeof globalThis.fetch {
  const { onCall } = options;
  const base = options.fetch ?? globalThis.fetch.bind(globalThis);
  const now = options.now ?? (() => performance.now());

  const report = (call: ObservedFetchCall): void => {
    try {
      onCall(call);
    } catch {
      // An observer must not change the result of a request.
    }
  };

  return async (input, init) => {
    const started = now();
    const { method, url } = describe(input, init);

    try {
      const response = await base(input, init);

      report({
        method,
        url,
        status: response.status,
        durationMs: now() - started,
      });

      return response;
    } catch (cause) {
      report({
        method,
        url,
        status: undefined,
        durationMs: now() - started,
        error: cause instanceof Error ? cause.name : "Error",
      });

      throw cause;
    }
  };
}
