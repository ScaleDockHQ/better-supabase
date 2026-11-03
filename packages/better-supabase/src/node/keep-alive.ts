import { importOptionalPeer, memoized } from "../core/optional-peer.ts";

/** The part of `undici` that `keepAliveFetch` uses, typed without importing it. */
export interface UndiciModule {
  readonly Agent: new (options: {
    readonly connections: number;
    readonly pipelining: number;
  }) => unknown;
  readonly fetch: (
    input: Parameters<typeof fetch>[0],
    init: Omit<RequestInit, "dispatcher"> & { dispatcher: unknown },
  ) => Promise<Response>;
}

export interface KeepAliveFetchOptions {
  /** Sockets kept open per origin. Defaults to 16. */
  readonly connections?: number;
  /**
   * Requests written on one socket before the first response returns. Defaults
   * to 1; PostgREST answers in order, so a higher value helps a burst of small
   * reads at the cost of head-of-line blocking.
   */
  readonly pipelining?: number;
  /** The module to use instead of loading `undici`, for tests. */
  readonly load?: () => Promise<UndiciModule | undefined>;
  /** The fetch used when `undici` is not installed. Defaults to `fetch`. */
  readonly fallback?: typeof fetch;
}

const DEFAULT_CONNECTIONS = 16;

function isUndici(value: unknown): value is UndiciModule {
  return (
    typeof value === "object" &&
    value !== null &&
    "Agent" in value &&
    "fetch" in value
  );
}

/**
 * A `fetch` for `createClient({ global: { fetch } })` that keeps `connections`
 * sockets open per origin and can pipeline requests on them. Node's built-in
 * fetch opens its own pool per realm and does not expose either setting.
 *
 * `undici` is an optional peer, loaded on the first request. Without it the
 * returned function calls the global `fetch`, so the code runs unchanged and
 * only the pool tuning is lost.
 *
 * ```ts
 * createClient(url, key, {
 *   global: { fetch: keepAliveFetch({ connections: 32 }) },
 * });
 * ```
 */
export function keepAliveFetch(
  options: KeepAliveFetchOptions = {},
): typeof fetch {
  const load =
    options.load ??
    (async () => {
      const loaded = await importOptionalPeer("undici");

      return isUndici(loaded) ? loaded : undefined;
    });

  const setup = memoized(async () => {
    const undici = await load();

    return undici === undefined
      ? undefined
      : {
          undici,
          dispatcher: new undici.Agent({
            connections: options.connections ?? DEFAULT_CONNECTIONS,
            pipelining: options.pipelining ?? 1,
          }),
        };
  });

  return async (input, init) => {
    const ready = await setup();

    if (ready === undefined) {
      return (options.fallback ?? fetch)(input, init);
    }

    return ready.undici.fetch(input, { ...init, dispatcher: ready.dispatcher });
  };
}
