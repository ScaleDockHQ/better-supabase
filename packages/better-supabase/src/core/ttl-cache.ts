export interface BoundedTtlCache<K, V> {
  /** The value, or `undefined` when it is missing or expired. */
  get(key: K): V | undefined;
  /** Stores `value` until `expiresAt` (epoch milliseconds). The oldest entry goes when the cache is full. */
  set(key: K, value: V, expiresAt: number): void;
  readonly size: number;
}

/** A map with a size cap and per-entry expiry, oldest-inserted evicted first. `now` is injectable for tests. */
export function boundedTtlCache<K, V>(options: {
  readonly max: number;
  readonly now?: () => number;
}): BoundedTtlCache<K, V> {
  const now = options.now ?? Date.now;
  const entries = new Map<K, { readonly value: V; readonly until: number }>();
  return {
    get(key) {
      const entry = entries.get(key);
      if (entry && entry.until > now()) {
        return entry.value;
      }
      entries.delete(key);
      return;
    },
    set(key, value, expiresAt) {
      entries.delete(key);
      if (entries.size >= options.max) {
        const oldest = entries.keys().next();
        if (!oldest.done) {
          entries.delete(oldest.value);
        }
      }
      entries.set(key, { value, until: expiresAt });
    },
    get size() {
      return entries.size;
    },
  };
}
