import type { SupabaseClient } from "@supabase/supabase-js";

import type { DbError } from "../core/errors.ts";
import type { Result } from "../core/result.ts";

import { dbError } from "../core/errors.ts";
import { err, ok } from "../core/result.ts";
import { chunkTags } from "../core/tag-chunks.ts";

export interface PostgresCacheStoreOptions {
  /** A client that may read and write the cache tables: the service role. */
  readonly client: SupabaseClient;
  /** Schema of the cache tables. Default: `public`. */
  readonly schema?: string;
  /** Default: `bsb_cache_entries`. */
  readonly entriesTable?: string;
  /** Default: `bsb_cache_tags`. */
  readonly tagsTable?: string;
}

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
}

export interface PostgresCacheStore {
  get(key: string): Promise<Result<StoredCacheEntry | undefined>>;
  set(entry: StoredCacheEntry): Promise<Result<true>>;
  /** Deletes the entries of a page path. */
  deletePath(path: string): Promise<Result<true>>;
  /** The state of each tag that was ever marked; unmarked tags are absent. */
  tagStates(
    tags: readonly string[],
  ): Promise<Result<ReadonlyMap<string, TagState>>>;
  /**
   * Marks tags. By default they are expired now. With `expireSeconds` they are
   * stale now and expire after the delay; with `staleOnly` they are stale and
   * keep their expiry.
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

interface EntryRow {
  readonly key: string;
  readonly value: string;
  readonly tags: string[];
  readonly stored_at: number;
  readonly expires_at: number;
  readonly path: string | null;
  readonly meta: Record<string, unknown>;
}

interface TagRow {
  readonly tag: string;
  readonly stale_at: number;
  readonly expired_at: number;
}

/**
 * Entries and tag states in two Postgres tables (`postgresCacheSql()` creates
 * them), so every instance reads what another wrote and a tag one expires is
 * expired on all. Methods return a `Result`; none throws.
 */
export function postgresCacheStore(
  options: PostgresCacheStoreOptions,
): PostgresCacheStore {
  const { client } = options;
  const schema = options.schema ?? "public";

  const entries = () =>
    client.schema(schema).from(options.entriesTable ?? "bsb_cache_entries");

  const tags = () =>
    client.schema(schema).from(options.tagsTable ?? "bsb_cache_tags");

  return {
    async get(key) {
      try {
        const { data, error } = await entries()
          .select("*")
          .eq("key", key)
          .maybeSingle<EntryRow>();

        if (error) {
          return err(failure("read", error));
        }

        if (!data) {
          return ok(undefined);
        }

        return ok({
          key: data.key,
          value: decodeBase64(data.value),
          tags: data.tags,
          storedAt: data.stored_at,
          expiresAt: data.expires_at,
          path: data.path ?? undefined,
          meta: data.meta,
        });
      } catch (error) {
        return err(failure("read", error));
      }
    },

    async set(entry) {
      try {
        const { error } = await entries().upsert({
          key: entry.key,
          value: encodeBase64(entry.value),
          tags: [...entry.tags],
          stored_at: entry.storedAt,
          expires_at: entry.expiresAt,
          path: entry.path ?? null,
          meta: entry.meta,
        });

        return error ? err(failure("write", error)) : ok(true);
      } catch (error) {
        return err(failure("write", error));
      }
    },

    async deletePath(path) {
      try {
        const { error } = await entries().delete().eq("path", path);

        return error ? err(failure("delete", error)) : ok(true);
      } catch (error) {
        return err(failure("delete", error));
      }
    },

    async tagStates(wanted) {
      const states = new Map<string, TagState>();

      try {
        for (const chunk of chunkTags(new Set(wanted))) {
          const { data, error } = await tags()
            .select("*")
            .in("tag", chunk)
            .overrideTypes<TagRow[], { merge: false }>();

          if (error) {
            return err(failure("tag read", error));
          }

          for (const row of data) {
            states.set(row.tag, {
              staleAt: row.stale_at,
              expiredAt: row.expired_at,
            });
          }
        }

        return ok(states);
      } catch (error) {
        return err(failure("tag read", error));
      }
    },

    async markTags(marked, markOptions = {}) {
      const now = markOptions.now ?? Date.now();
      const { expireSeconds } = markOptions;

      try {
        for (const chunk of chunkTags(new Set(marked))) {
          const current = await this.tagStates(chunk);

          if (!current.ok) {
            return current;
          }

          const rows = chunk.map((tag) => {
            const before = current.data.get(tag);

            return {
              tag,
              stale_at: now,
              expired_at: markOptions.staleOnly
                ? (before?.expiredAt ?? 0)
                : expireSeconds === undefined
                  ? now
                  : Math.max(
                      before?.expiredAt ?? 0,
                      now + expireSeconds * 1000,
                    ),
            };
          });

          const { error } = await tags().upsert(rows);

          if (error) {
            return err(failure("tag write", error));
          }
        }

        return ok(true);
      } catch (error) {
        return err(failure("tag write", error));
      }
    },

    async prune(now = Date.now()) {
      try {
        const { error } = await entries().delete().lt("expires_at", now);

        return error ? err(failure("prune", error)) : ok(true);
      } catch (error) {
        return err(failure("prune", error));
      }
    },
  };
}
