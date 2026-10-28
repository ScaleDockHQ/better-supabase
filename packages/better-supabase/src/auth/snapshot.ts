import type { JWTClaims } from "@supabase/server";

import type { AuthState } from "./resolve.ts";

import { AUTHZ_VERSION_CLAIM } from "../core/claim-names.ts";

/**
 * A verified user session, frozen and serializable. Times are epoch seconds,
 * like `AuthSession.expiresAt`, because the snapshot crosses `use cache`
 * serialization (ADR 0095).
 */
export interface SessionSnapshot<C = unknown> {
  readonly accessToken: string;
  readonly claims: Readonly<JWTClaims & C>;
  /** The Auth session id (`session_id`), or `null` for tokens without one. */
  readonly sessionId: string | null;
  readonly userId: string;
  /** Seconds since epoch, from `exp`. */
  readonly expiresAt: number | null;
  /** Seconds since epoch, from `iat`. */
  readonly issuedAt: number | null;
  /** The `authz_ver` claim, or `null` when the token has none. */
  readonly authzVersion: number | null;
}

/** Verified JWT claims, read by name. */
type Claims = Readonly<Record<string, unknown>>;

/** The `iat` claim in epoch seconds, or `null`. */
export function issuedAtOf(claims: Claims): number | null {
  const iat = claims["iat"];

  return typeof iat === "number" && Number.isFinite(iat) ? iat : null;
}

/** The `authz_ver` claim as a number, or `null` when absent or malformed. */
export function authzVersionOf(claims: Claims): number | null {
  const value = claims[AUTHZ_VERSION_CLAIM];

  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === "string" && /^\d+$/.test(value)) {
    return Number(value);
  }

  return null;
}

const branded = new WeakSet<object>();

const sources = new WeakMap<object, AuthState>();

/**
 * Whether `value` is a snapshot this process built from a verified token. A
 * snapshot that crossed serialization, or was built by hand, is not.
 */
export function isSessionSnapshot(value: unknown): value is SessionSnapshot {
  return typeof value === "object" && value !== null && branded.has(value);
}

/** The snapshot of a verified user, or `null` for any other caller. */
export function snapshotOf<C, P>(
  auth: AuthState<C, P>,
): SessionSnapshot<C> | null {
  if (auth.kind !== "user" || auth.token === "") {
    return null;
  }

  const sessionId = auth.claims["session_id"];

  const snapshot: SessionSnapshot<C> = Object.freeze({
    accessToken: auth.token,
    claims: Object.freeze({ ...auth.claims }),
    sessionId: typeof sessionId === "string" ? sessionId : null,
    userId: auth.user.id,
    expiresAt: auth.expiresAt,
    issuedAt: issuedAtOf(auth.claims),
    authzVersion: authzVersionOf(auth.claims),
  });

  branded.add(snapshot);
  sources.set(snapshot, auth);

  return snapshot;
}

/**
 * The verified auth state a branded snapshot was built from, or `undefined` for
 * a snapshot this process didn't build.
 */
export function authOfSnapshot<C, P>(
  snapshot: SessionSnapshot<C>,
): AuthState<C, P> | undefined {
  // SAFETY: snapshotOf stores the AuthState<C, P> it built SessionSnapshot<C> from.
  return sources.get(snapshot) as AuthState<C, P> | undefined;
}

/**
 * A stable cache key for a session: user, Auth session and authorization
 * version. It never contains the token, which rotates hourly and would churn
 * every key.
 */
export function sessionCacheKey(
  snapshot: Pick<SessionSnapshot, "userId" | "sessionId" | "authzVersion">,
): string {
  return `${snapshot.userId}:${snapshot.sessionId ?? "-"}:${String(snapshot.authzVersion ?? 0)}`;
}

export interface SessionMemoOptions {
  /** The most sessions kept; the least recently used goes first. Default: 1000. */
  readonly max?: number;
  /**
   * Milliseconds an entry lives at most. It never outlives the token's `exp`.
   * Default: 300000 (5 minutes).
   */
  readonly ttlMs?: number;
  /** Epoch milliseconds. */
  readonly now?: () => number;
}

export interface SessionMemoStats {
  /** Lookups answered by a stored or in-flight verification. */
  readonly hits: number;
  /** Lookups that ran a verification. */
  readonly misses: number;
  readonly size: number;
}

/**
 * Verified sessions by a SHA-256 of the access token. Every `use cache` scope
 * of a request resolves the same token; the first one verifies it and the
 * others await the same promise.
 */
export interface SessionMemo<T> {
  /**
   * The stored value for `token`, else `load()`'s. A `null` result is not
   * stored. Read the clock (call this) only after the request's dynamic APIs
   * (`cookies()`) have been awaited.
   */
  get(token: string, load: () => Promise<T | null>): Promise<T | null>;
  /** Stores a value verified elsewhere (a refresh, a sign-in). */
  seed(token: string, value: T): Promise<void>;
  /** Drops every entry `match` returns true for (a user's sessions). */
  evict(match: (value: T) => boolean): void;
  clear(): void;
  stats(): SessionMemoStats;
}

interface Entry<T> {
  readonly promise: Promise<T | null>;
  value?: T;
  until: number;
}

const encoder = new TextEncoder();

async function tokenKey(token: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(token));
  let hex = "";

  for (const byte of new Uint8Array(digest)) {
    hex += byte.toString(16).padStart(2, "0");
  }

  return hex;
}

/**
 * A bounded LRU of verified sessions. Keys derive only from the token, never
 * from a user id or a header, so one instance can serve many users at once
 * (Fluid compute). Create it once at module scope; `createServer` owns one.
 */
export function sessionMemo<T>(
  /**
   * Seconds since epoch when a stored value stops being valid (its token's
   * `exp`).
   */
  expiresAt: (value: T) => number | null,
  options: SessionMemoOptions = {},
): SessionMemo<T> {
  const max = Math.max(1, options.max ?? 1000);
  const ttlMs = options.ttlMs ?? 300_000;
  const clock = options.now ?? Date.now;
  const entries = new Map<string, Entry<T>>();
  let hits = 0;
  let misses = 0;

  const untilFor = (now: number, expiresAt: number | null): number =>
    expiresAt === null ? now + ttlMs : Math.min(now + ttlMs, expiresAt * 1000);

  const store = (key: string, entry: Entry<T>): void => {
    entries.delete(key);
    entries.set(key, entry);

    while (entries.size > max) {
      const oldest = entries.keys().next();

      if (oldest.done) {
        break;
      }

      entries.delete(oldest.value);
    }
  };

  return {
    async get(token, load) {
      const key = await tokenKey(token);
      const now = clock();
      const known = entries.get(key);

      if (known && known.until > now) {
        hits += 1;
        // Refresh the entry's place in the LRU order.
        store(key, known);

        return known.promise;
      }

      misses += 1;

      const entry: Entry<T> = {
        promise: load().then(
          (value) => {
            if (value === null) {
              if (entries.get(key) === entry) {
                entries.delete(key);
              }
            } else {
              entry.value = value;
              entry.until = Math.min(
                entry.until,
                untilFor(entry.until - ttlMs, expiresAt(value)),
              );
            }

            return value;
          },
          (cause: unknown) => {
            if (entries.get(key) === entry) {
              entries.delete(key);
            }

            throw cause;
          },
        ),
        until: now + ttlMs,
      };

      store(key, entry);

      return entry.promise;
    },

    async seed(token, value) {
      const key = await tokenKey(token);
      const until = untilFor(clock(), expiresAt(value));
      store(key, { promise: Promise.resolve(value), value, until });
    },

    evict(match) {
      for (const [key, entry] of entries) {
        if (entry.value !== undefined && match(entry.value)) {
          entries.delete(key);
        }
      }
    },

    clear() {
      entries.clear();
      hits = 0;
      misses = 0;
    },

    stats: () => ({ hits, misses, size: entries.size }),
  };
}
