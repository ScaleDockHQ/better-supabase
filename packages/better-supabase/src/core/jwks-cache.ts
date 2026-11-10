import type { Jwks, JwksOfOptions } from "./jws.ts";
import type { Result } from "./result.ts";

import { dbError } from "./errors.ts";
import { jwksOf } from "./jws.ts";
import { err, ok } from "./result.ts";

/** Where a key set comes from: inline, a URL fetched and cached, or a loader. */
export type JwksInput = Jwks | URL | (() => Promise<Jwks>);

export interface JwksSourceOptions extends JwksOfOptions {
  /**
   * How long a fetched key set is used before a refresh starts. Default: 300.
   * Past this, a caller still gets the cached set while a refresh runs in the
   * background, until `maxStaleSeconds` more have passed.
   */
  readonly cacheSeconds?: number;
  /**
   * How long a key set may still be served after `cacheSeconds`, while a
   * refresh runs in the background. Default: `cacheSeconds`. Past that the call
   * waits for the fetch and fails with `JWKS_FETCH_FAILED` when the fetch
   * fails. For a Supabase Auth key set, `cacheSeconds` plus this stays within
   * 600 seconds.
   */
  readonly maxStaleSeconds?: number;
  /** The least time between two fetches for an unknown `kid`. Default: 30. */
  readonly refetchSeconds?: number;
  readonly fetch?: typeof fetch;
  /** Epoch milliseconds. */
  readonly now?: () => number;
}

/**
 * A key set to verify with; `refresh` asks for a fresh copy after an unknown
 * `kid`.
 */
export type JwksSource = (refresh: boolean) => Promise<Result<Jwks>>;

/** A JWK Set as the issuer serves it, before any key is filtered out. */
export interface RawJwks {
  readonly keys: readonly Readonly<Record<string, unknown>>[];
}

/**
 * The longest a Supabase project's key set is served, cache window and stale
 * window together, whatever the options say. Signing keys rotate, and a revoked
 * key keeps verifying until the set is fetched again.
 */
const SUPABASE_JWKS_MAX_CACHE_SECONDS = 600;

/**
 * The fresh window and the extra time a stale set may still be served. A
 * Supabase key set keeps the two inside 600 seconds.
 */
function cacheWindows(
  cacheSeconds: number,
  maxStaleSeconds: number,
  supabase: boolean,
): { readonly cacheMs: number; readonly limitMs: number } {
  let cache = cacheSeconds;
  let stale = maxStaleSeconds;

  if (supabase) {
    cache = Math.min(cache, SUPABASE_JWKS_MAX_CACHE_SECONDS);
    stale = Math.min(stale, SUPABASE_JWKS_MAX_CACHE_SECONDS - cache);
  }

  const cacheMs = cache * 1000;

  return { cacheMs, limitMs: cacheMs + stale * 1000 };
}

const SUPABASE_JWKS_PATH = "/auth/v1/.well-known/jwks.json";

/** Whether `url` is a Supabase Auth key set (hosted, self-hosted or local). */
function isSupabaseJwksUrl(url: URL): boolean {
  return url.pathname.endsWith(SUPABASE_JWKS_PATH);
}

/** The most bytes read from a JWKS response. */
const MAX_JWKS_BYTES = 256 * 1024;

interface SharedEntry {
  cached: { readonly keys: RawJwks; readonly at: number } | undefined;
  pending: Promise<Result<RawJwks>> | undefined;
}

interface SharedRegistry {
  readonly byUrl: Map<string, SharedEntry>;
  byFetch: WeakMap<typeof fetch, Map<string, SharedEntry>>;
}

const REGISTRY = Symbol.for("better-supabase.jwks");

/**
 * One registry per process, on `globalThis`: Next.js loads the proxy and the
 * render in separate module graphs, and both must share one fetch.
 */
function registry(): SharedRegistry {
  // SAFETY: REGISTRY is a module symbol, so nothing else writes to that global slot.
  const scope = globalThis as { [REGISTRY]?: SharedRegistry };

  const shared = scope[REGISTRY] ?? {
    byUrl: new Map(),
    byFetch: new WeakMap(),
  };

  scope[REGISTRY] = shared;

  return shared;
}

function entryFor(url: string, customFetch?: typeof fetch): SharedEntry {
  const shared = registry();
  let byUrl = shared.byUrl;

  if (customFetch) {
    let custom = shared.byFetch.get(customFetch);

    if (!custom) {
      custom = new Map<string, SharedEntry>();
      shared.byFetch.set(customFetch, custom);
    }

    byUrl = custom;
  }

  let entry = byUrl.get(url);

  if (!entry) {
    byUrl.set(url, (entry = { cached: undefined, pending: undefined }));
  }

  return entry;
}

/** Forgets every shared key set. For tests and benchmarks. */
export function clearJwksCache(): void {
  const shared = registry();
  shared.byUrl.clear();
  shared.byFetch = new WeakMap();
}

/**
 * Forgets the shared key set of `url` (every fetch implementation's copy), so
 * the next verification fetches it again; no argument forgets all of them. Use
 * it after a key was revoked or rotated, instead of waiting for the cache.
 */
export function purgeJwks(url?: URL | string): void {
  if (url === undefined) {
    clearJwksCache();

    return;
  }

  const href = typeof url === "string" ? new URL(url).href : url.href;
  const shared = registry();

  shared.byUrl.delete(href);

  // A custom fetch keeps its own map, which a WeakMap can't enumerate: it is
  // replaced as a whole.
  shared.byFetch = new WeakMap();
}

function rawJwksOf(value: unknown): RawJwks {
  const keys: unknown[] =
    typeof value === "object" &&
    value !== null &&
    "keys" in value &&
    Array.isArray(value.keys)
      ? value.keys
      : [];

  return {
    keys: keys.filter(
      (key): key is Readonly<Record<string, unknown>> =>
        typeof key === "object" && key !== null,
    ),
  };
}

async function fetchRawJwks(
  url: URL,
  customFetch?: typeof fetch,
): Promise<Result<RawJwks>> {
  const response = await (customFetch ?? fetch)(url, {
    headers: { accept: "application/jwk-set+json, application/json" },
  });

  if (!response.ok) {
    return err(
      dbError("network", `The JWKS answered ${response.status}`, {
        code: "JWKS_FETCH_FAILED",
      }),
    );
  }

  const text = await response.text();

  if (text.length > MAX_JWKS_BYTES) {
    return err(
      dbError("network", "The JWKS response is too large", {
        code: "JWKS_FETCH_FAILED",
      }),
    );
  }

  return ok(rawJwksOf(JSON.parse(text)));
}

/**
 * The issuer's key set for `url`, shared by every verifier in the process. It
 * is fetched on first use and again after `cacheSeconds`. Until
 * `maxStaleSeconds` more have passed, a caller gets the cached set and the
 * refresh runs in the background. After that the call waits, and a failed fetch
 * is an error. A refresh for an unknown `kid` refetches at most once per
 * `refetchSeconds`, so a stream of forged `kid`s can't hammer the issuer.
 * Concurrent callers share one fetch. A failed fetch keeps the keys already
 * known while they are still inside that window.
 */
export async function sharedJwks(
  url: URL,
  refresh: boolean,
  options: Omit<JwksSourceOptions, "rsa"> = {},
): Promise<Result<RawJwks>> {
  const entry = entryFor(url.href, options.fetch);
  const now = options.now ?? Date.now;
  const seconds = options.cacheSeconds ?? 300;

  const { cacheMs, limitMs } = cacheWindows(
    seconds,
    options.maxStaleSeconds ?? seconds,
    isSupabaseJwksUrl(url),
  );

  const refetchMs = (options.refetchSeconds ?? 30) * 1000;

  const age = entry.cached ? now() - entry.cached.at : Number.POSITIVE_INFINITY;

  if (entry.cached && age < (refresh ? refetchMs : cacheMs)) {
    return ok(entry.cached.keys);
  }

  const refreshKeys = (): Promise<Result<RawJwks>> => {
    const pending = fetchRawJwks(url, options.fetch)
      .catch((cause: unknown) =>
        err(
          dbError(
            "network",
            `The JWKS could not be loaded: ${cause instanceof Error ? cause.message : String(cause)}`,
            { code: "JWKS_FETCH_FAILED" },
          ),
        ),
      )
      .then((result) => {
        if (result.ok) {
          entry.cached = { keys: result.data, at: now() };
        }

        return result;
      })
      .finally(() => {
        if (entry.pending === pending) {
          entry.pending = undefined;
        }
      });

    entry.pending = pending;

    return pending;
  };

  // A routine expiry serves the keys already known and refreshes behind the
  // response, until the stale window ends. An unknown kid still waits, because
  // the cached set cannot verify it.
  if (entry.cached && !refresh && age < limitMs) {
    entry.pending ??= refreshKeys();

    return ok(entry.cached.keys);
  }

  entry.pending ??= refreshKeys();

  const result = await entry.pending;

  return !result.ok && entry.cached && age < limitMs
    ? ok(entry.cached.keys)
    : result;
}

/**
 * A cached key set. A URL goes through `sharedJwks`, so every verifier in the
 * process shares its fetch; a loader is called on first use and cached the same
 * way.
 */
export function jwksSource(
  input: JwksInput,
  options: JwksSourceOptions = {},
): JwksSource {
  const parse = (value: unknown): Jwks =>
    jwksOf(value, options.rsa === undefined ? {} : { rsa: options.rsa });

  if (input instanceof URL) {
    const { rsa: _rsa, ...shared } = options;

    return async (refresh) => {
      const result = await sharedJwks(input, refresh, shared);

      return result.ok ? ok(parse(result.data)) : result;
    };
  }

  if (typeof input !== "function") {
    const keys = parse(input);

    return () => Promise.resolve(ok(keys));
  }

  const now = options.now ?? Date.now;
  const seconds = options.cacheSeconds ?? 300;

  const { cacheMs, limitMs } = cacheWindows(
    seconds,
    options.maxStaleSeconds ?? seconds,
    false,
  );

  const refetchMs = (options.refetchSeconds ?? 30) * 1000;
  let cached: { readonly keys: Jwks; readonly at: number } | undefined;
  let pending: Promise<Result<Jwks>> | undefined;

  return async (refresh) => {
    const age = cached ? now() - cached.at : Number.POSITIVE_INFINITY;

    if (cached && age < (refresh ? refetchMs : cacheMs)) {
      return ok(cached.keys);
    }

    const load = (): Promise<Result<Jwks>> => {
      const flight = input()
        .then((value) => ok(parse(value)))
        .catch((cause: unknown) =>
          err(
            dbError(
              "network",
              `The JWKS could not be loaded: ${cause instanceof Error ? cause.message : String(cause)}`,
              { code: "JWKS_FETCH_FAILED" },
            ),
          ),
        )
        .then((result) => {
          if (result.ok) {
            cached = { keys: result.data, at: now() };
          }

          return result;
        })
        .finally(() => {
          if (pending === flight) {
            pending = undefined;
          }
        });

      pending = flight;

      return flight;
    };

    if (cached && !refresh && age < limitMs) {
      pending ??= load();

      return ok(cached.keys);
    }

    pending ??= load();

    const result = await pending;

    return !result.ok && cached && age < limitMs ? ok(cached.keys) : result;
  };
}
