/** `@react-native-async-storage/async-storage` or any async string store. */
export interface AsyncStorageLike {
  getItem(key: string): Promise<string | null>;
  setItem(key: string, value: string): Promise<void>;
  removeItem(key: string): Promise<void>;
}

/** `react-native-mmkv`: `delete` up to v3, `remove` from v4. */
export interface MmkvLike {
  getString(key: string): string | undefined;
  set(key: string, value: string): void;
  delete?(key: string): void;
  remove?(key: string): unknown;
}

export type KeyValueStoreLike = AsyncStorageLike | MmkvLike;

/** A store with async `get`, `set` and `remove`, whichever kind it wraps. */
export interface KeyValue {
  get(key: string): Promise<string | null>;
  set(key: string, value: string): Promise<void>;
  remove(key: string): Promise<void>;
}

function isMmkv(store: KeyValueStoreLike): store is MmkvLike {
  return "getString" in store;
}

export function keyValue(store: KeyValueStoreLike): KeyValue {
  if (!isMmkv(store)) {
    return {
      get: (key) => store.getItem(key),
      set: (key, value) => store.setItem(key, value),
      remove: (key) => store.removeItem(key),
    };
  }
  return {
    get: (key) => Promise.resolve(store.getString(key) ?? null),
    set: (key, value) => {
      store.set(key, value);
      return Promise.resolve();
    },
    remove: (key) => {
      if (store.remove) store.remove(key);
      else store.delete?.(key);
      return Promise.resolve();
    },
  };
}
