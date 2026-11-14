import type { Jwks, JwksOfOptions } from "./jws.ts";
import type { Result } from "./result.ts";

import { dbError } from "./errors.ts";
import { jwksOf } from "./jws.ts";
import { err, ok } from "./result.ts";

/** Where a key set comes from: inline, a URL fetched and cached, or a loader. */
export type JwksInput = Jwks | URL | (() => Promise<Jwks>);

/**
 * A key-value store that instances share, holding the key sets they fetched so
 * a new instance can skip the fetch. The Vercel Runtime Cache (`getCache()`
 * from `@vercel/functions`) has this shape; `vercelRuntimeCache` wraps it.
 */
export interface JwksStore {
  get(key: string): Promise<unknown>;
  /** `ttl` is in seconds. */
  set(key: string, value: unknown, options?: { ttl?: number }): Promise<void>;
}

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
  /**
   * Shares a fetched key set (URL inputs only) between instances. A stored copy
   * keeps the time of its original fetch, so it is used only inside the same
   * windows as a copy in memory: a Supabase key set is still never served more
   * than 600 seconds after it was fetched. A store that fails or takes longer
   * than 500 ms is skipped, and the key set is fetched instead.
   */
  readonly store?: JwksStore;
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

/** A fetched key set and the epoch milliseconds of its fetch. */
interface CachedJwks {
  readonly keys: RawJwks;
  readonly at: number;
}

interface SharedEntry {
  cached: CachedJwks | undefined;
  pending: Promise<Result<RawJwks>> | undefined;
}

/**
 * What `purgeJwks` asked of the stores: a stored copy fetched before the purge
 * must not come back. A purge is numbered, and the first store read after it
 * fixes the cutoff with that call's clock.
 */
interface StorePurges {
  sequence: number;
  all: number;
  readonly byUrl: Map<string, number>;
  readonly seen: Map<string, number>;
  readonly cutoff: Map<string, number>;
}

interface SharedRegistry {
  readonly byUrl: Map<string, SharedEntry>;
  byFetch: WeakMap<typeof fetch, Map<string, SharedEntry>>;
  /** Unset in a registry an older copy of this module created. */
  purges?: StorePurges;
}

function purgesOf(shared: SharedRegistry): StorePurges {
  shared.purges ??= {
    sequence: 0,
    all: 0,
    byUrl: new Map(),
    seen: new Map(),
    cutoff: new Map(),
  };

  return shared.purges;
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

/**
 * Forgets every shared key set, as a new process would start. For tests and
 * benchmarks.
 */
export function clearJwksCache(): void {
  const shared = registry();
  shared.byUrl.clear();
  shared.byFetch = new WeakMap();
  delete shared.purges;
}

/**
 * Forgets the shared key set of `url` (every fetch implementation's copy), so
 * the next verification fetches it again; no argument forgets all of them. Use
 * it after a key was revoked or rotated, instead of waiting for the cache. A
 * copy in a `store` that was fetched before the purge is not used again.
 */
export function purgeJwks(url?: URL | string): void {
  if (url === undefined) {
    clearJwksCache();
    const purges = purgesOf(registry());
    purges.sequence += 1;
    purges.all = purges.sequence;

    return;
  }

  const href = typeof url === "string" ? new URL(url).href : url.href;
  const shared = registry();

  shared.byUrl.delete(href);

  // A custom fetch keeps its own map, which a WeakMap can't enumerate: it is
  // replaced as a whole.
  shared.byFetch = new WeakMap();

  const purges = purgesOf(shared);
  purges.sequence += 1;
  purges.byUrl.set(href, purges.sequence);
}

/**
 * The fetch time a stored copy of `href` must be newer than: the time of the
 * first store read after the latest purge.
 */
function storeCutoff(href: string, now: number): number {
  const purges = purgesOf(registry());
  const latest = Math.max(purges.byUrl.get(href) ?? 0, purges.all);

  if (latest > (purges.seen.get(href) ?? 0)) {
    purges.seen.set(href, latest);
    purges.cutoff.set(href, now);
  }

  return purges.cutoff.get(href) ?? Number.NEGATIVE_INFINITY;
}

/** The longest a store read may take before the key set is fetched instead. */
const STORE_READ_MS = 500;

const storeKeyOf = (url: URL): string => `better-supabase:jwks:${url.href}`;

/** A stored copy, when it has the shape `writeStored` gives it. */
function cachedJwksOf(value: unknown): CachedJwks | undefined {
  if (
    typeof value !== "object" ||
    value === null ||
    !("at" in value) ||
    !("keys" in value) ||
    typeof value.at !== "number" ||
    !Number.isFinite(value.at) ||
    typeof value.keys !== "object" ||
    value.keys === null ||
    !("keys" in value.keys) ||
    !Array.isArray(value.keys.keys)
  ) {
    return undefined;
  }

  return { keys: rawJwksOf(value.keys), at: value.at };
}

/** The store's copy of `url`, or `undefined` when it fails or is slow. */
async function readStored(
  store: JwksStore,
  url: URL,
): Promise<CachedJwks | undefined> {
  let timer: ReturnType<typeof setTimeout> | undefined;

  const late = new Promise<undefined>((resolve) => {
    timer = setTimeout(resolve, STORE_READ_MS, undefined);
  });

  try {
    const value = await Promise.race([
      Promise.resolve().then(() => store.get(storeKeyOf(url))),
      late,
    ]);

    return cachedJwksOf(value);
  } catch {
    return undefined;
  } finally {
    clearTimeout(timer);
  }
}

/** Writes a fetched copy without waiting for the store, and ignores failures. */
function writeStored(
  store: JwksStore,
  url: URL,
  cached: CachedJwks,
  ttl: number,
): void {
  try {
    void Promise.resolve(
      store.set(
        storeKeyOf(url),
        { keys: { keys: cached.keys.keys }, at: cached.at },
        { ttl },
      ),
    ).catch(() => undefined);
  } catch {
    // A store that throws is skipped like one that rejects.
  }
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
 * known while they are still inside that window. With a `store`, a newer copy
 * another instance fetched is used instead of a fetch while it is inside the
 * same windows, and every fetch is written back.
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
  const { store } = options;

  const ageOf = (): number =>
    entry.cached ? now() - entry.cached.at : Number.POSITIVE_INFINITY;

  let age = ageOf();

  if (entry.cached && age < (refresh ? refetchMs : cacheMs)) {
    return ok(entry.cached.keys);
  }

  // Another instance may have fetched a newer copy. It counts from its own
  // fetch time, so it fits the same windows as one fetched here.
  if (store && !entry.pending) {
    const stored = await readStored(store, url);
    const time = now();
    const cutoff = storeCutoff(url.href, time);

    if (
      stored &&
      stored.at <= time &&
      stored.at > cutoff &&
      stored.at > (entry.cached?.at ?? Number.NEGATIVE_INFINITY) &&
      time - stored.at < (refresh ? refetchMs : limitMs)
    ) {
      entry.cached = stored;
      age = ageOf();

      if (age < (refresh ? refetchMs : cacheMs)) {
        return ok(stored.keys);
      }
    }
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

          if (store) {
            writeStored(
              store,
              url,
              entry.cached,
              Math.max(1, Math.ceil(limitMs / 1000)),
            );
          }
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
