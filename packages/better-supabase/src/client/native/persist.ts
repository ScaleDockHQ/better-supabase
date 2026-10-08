import type { KeyValueStoreLike } from "./key-value.ts";

import { keyValue } from "./key-value.ts";

/**
 * TanStack Query's `Persister`: pass it as `persistOptions.persister` to
 * `PersistQueryClientProvider` or `persistQueryClient`.
 */
export interface QueryPersister<T> {
  persistClient(client: T): Promise<void>;
  restoreClient(): Promise<T | undefined>;
  removeClient(): Promise<void>;
}

export interface PersistQueryCacheOptions {
  /** Defaults to `better-supabase.query-cache`. */
  readonly key?: string;
  /** Writes at most once per interval, keeping the latest cache. Defaults to 1000 ms. */
  readonly throttleMs?: number;
}

/**
 * Persists the query cache to MMKV or AsyncStorage, so a cold start shows
 * the last rows before the first fetch. The provider's `clearOnUserChange`
 * drops them when another user signs in.
 *
 * ```tsx
 * <PersistQueryClientProvider client={queryClient} persistOptions={{ persister: persistQueryCache(storage) }}>
 * ```
 */
export function persistQueryCache<T>(
  storage: KeyValueStoreLike,
  options: PersistQueryCacheOptions = {},
): QueryPersister<T> {
  const store = keyValue(storage);
  const key = options.key ?? "better-supabase.query-cache";
  const throttleMs = options.throttleMs ?? 1000;
  let pending: { readonly value: string } | undefined;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let writing: Promise<void> = Promise.resolve();

  const flush = (): Promise<void> => {
    timer = undefined;
    const next = pending;
    pending = undefined;
    if (!next) return writing;
    writing = writing.then(() => store.set(key, next.value));
    return writing;
  };

  return {
    persistClient(client) {
      pending = { value: JSON.stringify(client) };
      timer ??= setTimeout(() => void flush(), throttleMs);
      return Promise.resolve();
    },
    async restoreClient(): Promise<T | undefined> {
      const raw = await store.get(key);
      let restored: T | undefined;
      if (raw !== null) {
        try {
          // SAFETY: only `persistClient` writes this key, with a serialized T.
          restored = JSON.parse(raw) as T;
        } catch {
          // A corrupt entry restores nothing; the next write replaces it.
        }
      }
      return restored;
    },
    async removeClient() {
      if (timer !== undefined) clearTimeout(timer);
      timer = undefined;
      pending = undefined;
      await writing;
      await store.remove(key);
    },
  };
}
