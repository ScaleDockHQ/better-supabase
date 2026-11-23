import type { SupabaseClient } from "@supabase/supabase-js";

import type { DbError } from "../core/errors.ts";
import type { Result } from "../core/result.ts";
import type { PostgresCacheNames } from "./names.ts";

import { dbError } from "../core/errors.ts";
import { err, ok } from "../core/result.ts";
import { chunkTags } from "../core/tag-chunks.ts";
import { postgresCacheNames } from "./names.ts";

/** A Postgres connection that runs SQL; `better-supabase/postgres` returns one. */
export interface PostgresCacheSqlClient {
  queryRaw<T = Record<string, unknown>>(
    text: string,
    params?: unknown[],
  ): Promise<T[]>;
}

export interface PostgresCacheTables {
  /** Schema of the cache tables. Default: `public`. */
  readonly schema?: string;
  /** Default: `bsb_cache_entries`. */
  readonly entriesTable?: string;
  /** Default: `bsb_cache_tags`. */
  readonly tagsTable?: string;
  /** The `functionPrefix` given to `postgresCacheSql`. Default: `bsb_cache`. */
  readonly functionPrefix?: string;
  /**
   * Called the first time the functions of `postgresCacheSql()` are missing.
   * The store then uses the tables (two queries per read) and tries the
   * functions again after a minute.
   */
  readonly onError?: ((error: DbError) => void) | undefined;
}

export type PostgresCacheStoreOptions = PostgresCacheTables &
  (
    | {
        /** A client that may read and write the cache tables: the service role. */
        readonly client: SupabaseClient;
        readonly transport?: undefined;
      }
    | {
        /**
         * Talk to Postgres over a pool instead of PostgREST, as a role that may
         * use the cache tables.
         */
        readonly transport: { readonly postgres: PostgresCacheSqlClient };
        readonly client?: undefined;
      }
  );

/**
 * Where a handler or provider keeps its entries: a service role client, a pool,
 * or an existing store.
 */
export type PostgresCacheSource =
  | {
      readonly client: SupabaseClient | PostgresCacheStore;
      readonly transport?: undefined;
    }
  | {
      readonly transport: { readonly postgres: PostgresCacheSqlClient };
      readonly client?: undefined;
    };

/** An entry as the handlers keep it. Times are epoch milliseconds. */
export interface StoredCacheEntry {
  readonly key: string;
  readonly value: Uint8Array<ArrayBuffer>;
  readonly tags: readonly string[];
  readonly storedAt: number;
  /** Hard limit: past it the entry is a miss. */
  readonly expiresAt: number;
  /** Path of the page, for `invalidate({ path })`. */
  readonly path?: string | undefined;
  /** Handler specific fields, kept as JSON. */
  readonly meta: Readonly<Record<string, unknown>>;
}

/** When a tag was last made stale or expired, `0` for never. */
export interface TagState {
  readonly staleAt: number;
  readonly expiredAt: number;
  /** A delayed expiry from `revalidateTag(tag, { expire })`. */
  readonly expireAfter?: number;
}

/** A live entry and whether one of its tags went stale after it was stored. */
export interface CacheLookup {
  readonly entry: StoredCacheEntry;
  readonly stale: boolean;
}

export interface PostgresCacheStore {
  get(key: string): Promise<Result<StoredCacheEntry | undefined>>;
  /**
   * The entry unless it is past its hard limit or one of its tags or `softTags`
   * expired after it was stored, in one round trip.
   */
  lookup(
    key: string,
    softTags?: readonly string[],
    now?: number,
  ): Promise<Result<CacheLookup | undefined>>;
  set(entry: StoredCacheEntry): Promise<Result<true>>;
  /** Deletes one entry. */
  delete(key: string): Promise<Result<true>>;
  /** Deletes the entries of a page path. */
  deletePath(path: string): Promise<Result<true>>;
  /** The state of each tag that was ever marked; unmarked tags are absent. */
  tagStates(
    tags: readonly string[],
  ): Promise<Result<ReadonlyMap<string, TagState>>>;
  /**
   * Marks tags. By default they are expired now. With `expireSeconds` they are
   * stale now and expire after the delay; with `staleOnly` they are stale and
   * keep their expiry. Concurrent calls never undo each other.
   */
  markTags(
    tags: readonly string[],
    options?: {
      readonly expireSeconds?: number;
      readonly staleOnly?: boolean;
      readonly now?: number;
    },
  ): Promise<Result<true>>;
  /** Deletes entries past their hard limit; run it from `pg_cron` or a job. */
  prune(now?: number): Promise<Result<true>>;
  /**
   * Whether `holder` may fill `key` for the next `ttlMs` milliseconds. Exactly
   * one caller wins until the lease runs out or `release` ends it. Without the
   * lease function of `postgresCacheSql()` every caller wins.
   */
  lease(
    key: string,
    holder: string,
    ttlMs: number,
    now?: number,
  ): Promise<Result<boolean>>;
  /** Ends `holder`'s lease on `key`; another holder's lease stays. */
  release(key: string, holder: string): Promise<Result<true>>;
}

function failure(action: string, cause: unknown): DbError {
  const message =
    typeof cause === "object" && cause !== null && "message" in cause
      ? String(cause.message)
      : String(cause);

  return dbError("unexpected", `Postgres cache: ${action} failed: ${message}`);
}

export function encodeBase64(bytes: Uint8Array): string {
  let binary = "";

  for (let index = 0; index < bytes.length; index += 0x80_00) {
    binary += String.fromCodePoint(...bytes.subarray(index, index + 0x80_00));
  }

  return btoa(binary);
}

export function decodeBase64(text: string): Uint8Array<ArrayBuffer> {
  const binary = atob(text);
  const bytes = new Uint8Array(binary.length);

  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.codePointAt(index) ?? 0;
  }

  return bytes;
}

export interface EntryRow {
  readonly key: string;
  readonly value: string;
  readonly tags: string[];
  // A pool returns `bigint` columns as strings.
  readonly stored_at: number | string;
  readonly expires_at: number | string;
  readonly path: string | null;
  readonly meta: Record<string, unknown>;
}

export interface LookupRow extends EntryRow {
  readonly stale: boolean;
}

export interface TagRow {
  readonly tag: string;
  readonly stale_at: number | string;
  readonly expired_at: number | string;
  readonly expire_after?: number | string;
}

interface WriteTagRow {
  readonly tag: string;
  readonly stale_at: number;
  readonly expired_at: number;
}

type MarkMode = "expire" | "delay" | "stale";

/** Raised by a backend when the function is not installed. */
export const MISSING: unique symbol = Symbol("missing");

/** What the store needs from PostgREST or a pool. Methods throw on errors. */
export interface Backend {
  selectEntry(key: string): Promise<EntryRow | undefined>;
  callGet(
    key: string,
    softTags: readonly string[],
    now: number,
  ): Promise<LookupRow | undefined | typeof MISSING>;
  upsertEntry(row: EntryRow): Promise<void>;
  deleteWhere(column: "key" | "path", value: string): Promise<void>;
  deleteExpired(now: number): Promise<void>;
  selectTags(tags: readonly string[]): Promise<TagRow[]>;
  upsertTags(rows: readonly WriteTagRow[]): Promise<void>;
  callMarkTags(
    tags: readonly string[],
    mode: MarkMode,
    expireSeconds: number,
    now: number,
  ): Promise<true | typeof MISSING>;
  callLease(
    key: string,
    holder: string,
    ttlMs: number,
    now: number,
  ): Promise<boolean | typeof MISSING>;
  deleteLease(key: string, holder: string): Promise<void>;
}

export function restBackend(
  client: SupabaseClient,
  names: PostgresCacheNames,
): Backend {
  const db = () => client.schema(names.schema);
  const entries = () => db().from(names.entriesTable);
  const tags = () => db().from(names.tagsTable);

  const raise = (error: { message: string } | null): void => {
    if (error) {
      throw new Error(error.message, { cause: error });
    }
  };

  // PostgREST answers PGRST202 for a function it does not know.
  const missing = (error: { code?: string } | null): boolean =>
    error?.code === "PGRST202";

  return {
    async selectEntry(key) {
      const { data, error } = await entries()
        .select("*")
        .eq("key", key)
        .maybeSingle<EntryRow>();

      raise(error);

      return data ?? undefined;
    },
    async callGet(key, softTags, now) {
      const { data, error } = await db()
        .rpc(names.getFunction, {
          p_key: key,
          p_soft_tags: [...softTags],
          p_now: now,
        })
        .maybeSingle<LookupRow>();

      if (missing(error)) {
        return MISSING;
      }

      raise(error);

      return data ?? undefined;
    },
    async upsertEntry(row) {
      const { error } = await entries().upsert(row);
      raise(error);
    },
    async deleteWhere(column, value) {
      const { error } = await entries().delete().eq(column, value);
      raise(error);
    },
    async deleteExpired(now) {
      const { error } = await entries().delete().lt("expires_at", now);
      raise(error);
    },
    async selectTags(chunk) {
      const { data, error } = await tags()
        .select("*")
        .in("tag", [...chunk])
        .overrideTypes<TagRow[], { merge: false }>();

      raise(error);

      return data ?? [];
    },
    async upsertTags(rows) {
      const { error } = await tags().upsert([...rows]);
      raise(error);
    },
    async callMarkTags(chunk, mode, expireSeconds, now) {
      const { error } = await db().rpc(names.markTagsFunction, {
        p_tags: [...chunk],
        p_mode: mode,
        p_expire_seconds: expireSeconds,
        p_now: now,
      });

      if (missing(error)) {
        return MISSING;
      }

      raise(error);

      return true;
    },
    async callLease(key, holder, ttlMs, now) {
      const { data, error } = await db()
        .rpc(names.leaseFunction, {
          p_key: key,
          p_holder: holder,
          p_ttl_ms: ttlMs,
          p_now: now,
        })
        .overrideTypes<boolean, { merge: false }>();

      if (missing(error)) {
        return MISSING;
      }

      raise(error);

      return data === true;
    },
    async deleteLease(key, holder) {
      const { error } = await db()
        .from(names.leasesTable)
        .delete()
        .eq("key", key)
        .eq("holder", holder);

      raise(error);
    },
  };
}

function entryOf(row: EntryRow): StoredCacheEntry {
  return {
    key: row.key,
    value: decodeBase64(row.value),
    tags: row.tags,
    storedAt: Number(row.stored_at),
    expiresAt: Number(row.expires_at),
    path: row.path ?? undefined,
    meta: row.meta,
  };
}

function stateOf(row: TagRow): TagState {
  return {
    staleAt: Number(row.stale_at),
    expiredAt: Number(row.expired_at),
    ...(row.expire_after === undefined
      ? {}
      : { expireAfter: Number(row.expire_after) }),
  };
}

const expiredBetween = (at: number, since: number, now: number): boolean =>
  at > since && at <= now;

/**
 * Whether a tag of `tags` expired after `since`: the check `lookup` makes in
 * SQL.
 */
function tagsExpiredSince(
  states: ReadonlyMap<string, TagState>,
  tags: readonly string[],
  since: number,
  now: number,
): boolean {
  return tags.some((tag) => {
    const state = states.get(tag);

    return (
      state !== undefined &&
      (expiredBetween(state.expiredAt, since, now) ||
        expiredBetween(state.expireAfter ?? 0, since, now))
    );
  });
}

export function isStore(
  client: SupabaseClient | PostgresCacheStore,
): client is PostgresCacheStore {
  return "tagStates" in client && "markTags" in client;
}

/** A store over `backend`; `postgresCacheStore` picks the backend. */
export function createCacheStore(
  backend: Backend,
  options: PostgresCacheTables,
): PostgresCacheStore {
  const names = postgresCacheNames(options);
  const { onError } = options;

  // When a function is missing the store uses the tables, and tries the
  // function again after a minute: PostgREST may not have reloaded yet.
  let missingSince: number | undefined;
  let reported = false;
  // Set when the lease function is missing: every caller then fills, and
  // nothing is released.
  let leaseMissingSince: number | undefined;

  const functionsReady = (): boolean =>
    missingSince === undefined || Date.now() - missingSince > 60_000;

  const fallBack = (): void => {
    missingSince = Date.now();

    if (!reported) {
      reported = true;
      onError?.(
        dbError(
          "unexpected",
          `Postgres cache: ${names.getFunction} or ${names.markTagsFunction} is missing, so each read takes two queries; run postgresCacheSql() again in a migration.`,
        ),
      );
    }
  };

  const tagStates = async (
    wanted: readonly string[],
  ): Promise<Result<ReadonlyMap<string, TagState>>> => {
    const states = new Map<string, TagState>();

    try {
      for (const chunk of chunkTags(new Set(wanted))) {
        for (const row of await backend.selectTags(chunk)) {
          states.set(row.tag, stateOf(row));
        }
      }

      return ok(states);
    } catch (error) {
      return err(failure("tag read", error));
    }
  };

  const get = async (
    key: string,
  ): Promise<Result<StoredCacheEntry | undefined>> => {
    try {
      const row = await backend.selectEntry(key);

      return ok(row ? entryOf(row) : undefined);
    } catch (error) {
      return err(failure("read", error));
    }
  };

  const lookupInTwo = async (
    key: string,
    softTags: readonly string[],
    now: number,
  ): Promise<Result<CacheLookup | undefined>> => {
    const found = await get(key);

    if (!found.ok || !found.data || found.data.expiresAt <= now) {
      return found.ok ? ok(undefined) : found;
    }

    const entry = found.data;
    const tags = [...entry.tags, ...softTags];
    const states = await tagStates(tags);

    if (!states.ok) {
      return states;
    }

    if (tagsExpiredSince(states.data, tags, entry.storedAt, now)) {
      return ok(undefined);
    }

    return ok({
      entry,
      stale: tags.some(
        (tag) => (states.data.get(tag)?.staleAt ?? 0) > entry.storedAt,
      ),
    });
  };

  // The read-then-write an install without the functions needs; two
  // concurrent calls can lose a delayed expiry here.
  const markInTwo = async (
    chunk: readonly string[],
    mode: MarkMode,
    expireSeconds: number,
    now: number,
  ): Promise<Result<true>> => {
    const current = await tagStates(chunk);

    if (!current.ok) {
      return current;
    }

    await backend.upsertTags(
      chunk.map((tag) => {
        const before = current.data.get(tag);

        return {
          tag,
          stale_at: now,
          expired_at:
            mode === "stale"
              ? (before?.expiredAt ?? 0)
              : mode === "expire"
                ? now
                : Math.max(before?.expiredAt ?? 0, now + expireSeconds * 1000),
        };
      }),
    );

    return ok(true);
  };

  return {
    get,
    tagStates,

    async lookup(key, softTags = [], at = Date.now()) {
      const now = Math.floor(at);

      if (!functionsReady()) {
        return lookupInTwo(key, softTags, now);
      }

      try {
        const row = await backend.callGet(key, softTags, now);

        if (row === MISSING) {
          fallBack();

          return await lookupInTwo(key, softTags, now);
        }

        missingSince = undefined;

        return ok(row ? { entry: entryOf(row), stale: row.stale } : undefined);
      } catch (error) {
        return err(failure("read", error));
      }
    },

    async set(entry) {
      try {
        await backend.upsertEntry({
          key: entry.key,
          value: encodeBase64(entry.value),
          tags: [...entry.tags],
          // Next.js stamps entries with a fractional millisecond; the columns
          // are bigint. Rounding down only makes an entry look older.
          stored_at: Math.floor(entry.storedAt),
          expires_at: Math.floor(entry.expiresAt),
          path: entry.path ?? null,
          meta: { ...entry.meta },
        });

        return ok(true);
      } catch (error) {
        return err(failure("write", error));
      }
    },

    async delete(key) {
      try {
        await backend.deleteWhere("key", key);

        return ok(true);
      } catch (error) {
        return err(failure("delete", error));
      }
    },

    async deletePath(path) {
      try {
        await backend.deleteWhere("path", path);

        return ok(true);
      } catch (error) {
        return err(failure("delete", error));
      }
    },

    async markTags(marked, markOptions = {}) {
      const now = Math.floor(markOptions.now ?? Date.now());
      const expireSeconds = markOptions.expireSeconds ?? 0;

      const mode: MarkMode = markOptions.staleOnly
        ? "stale"
        : markOptions.expireSeconds === undefined
          ? "expire"
          : "delay";

      try {
        for (const chunk of chunkTags(new Set(marked))) {
          if (functionsReady()) {
            const called = await backend.callMarkTags(
              chunk,
              mode,
              expireSeconds,
              now,
            );

            if (called !== MISSING) {
              missingSince = undefined;
              continue;
            }

            fallBack();
          }

          const written = await markInTwo(chunk, mode, expireSeconds, now);

          if (!written.ok) {
            return written;
          }
        }

        return ok(true);
      } catch (error) {
        return err(failure("tag write", error));
      }
    },

    async lease(key, holder, ttlMs, at = Date.now()) {
      if (
        leaseMissingSince !== undefined &&
        Date.now() - leaseMissingSince <= 60_000
      ) {
        return ok(true);
      }

      try {
        const won = await backend.callLease(
          key,
          holder,
          Math.max(1, Math.floor(ttlMs)),
          Math.floor(at),
        );

        if (won === MISSING) {
          leaseMissingSince = Date.now();

          return ok(true);
        }

        leaseMissingSince = undefined;

        return ok(won);
      } catch (error) {
        return err(failure("lease", error));
      }
    },

    async release(key, holder) {
      if (leaseMissingSince !== undefined) {
        return ok(true);
      }

      try {
        await backend.deleteLease(key, holder);

        return ok(true);
      } catch (error) {
        return err(failure("release", error));
      }
    },

    async prune(now = Date.now()) {
      try {
        await backend.deleteExpired(Math.floor(now));

        return ok(true);
      } catch (error) {
        return err(failure("prune", error));
      }
    },
  };
}
