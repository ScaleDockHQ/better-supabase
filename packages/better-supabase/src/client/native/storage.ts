/** The part of `expo-secure-store` the storage adapter uses. */
export interface SecureStoreLike {
  getItemAsync(key: string): Promise<string | null>;
  setItemAsync(key: string, value: string): Promise<void>;
  deleteItemAsync(key: string): Promise<void>;
}

/** The storage interface supabase-js `auth.storage` takes. */
export interface AuthStorage {
  getItem(key: string): Promise<string | null>;
  setItem(key: string, value: string): Promise<void>;
  removeItem(key: string): Promise<void>;
}

export interface SecureStorageOptions {
  /**
   * Characters per stored value. Defaults to 1800: iOS warns above 2048
   * bytes, and a Supabase session with custom claims is larger than that.
   */
  readonly chunkSize?: number;
}

/** expo-secure-store keys allow letters, digits, `.`, `-` and `_` only. */
function safeKey(key: string): string {
  return key.replaceAll(/[^\w.-]/g, "_");
}

/**
 * Supabase Auth storage on the device keychain (`expo-secure-store`),
 * split into chunks so sessions above the platform's value size fit.
 *
 * ```ts
 * import * as SecureStore from 'expo-secure-store';
 * createClient(url, key, { auth: { storage: secureStorage(SecureStore) } });
 * ```
 */
export function secureStorage(
  store: SecureStoreLike,
  options: SecureStorageOptions = {},
): AuthStorage {
  const size = options.chunkSize ?? 1800;
  if (!Number.isInteger(size) || size < 1)
    throw new TypeError(
      "better-supabase: chunkSize must be a positive integer",
    );
  const countKey = (key: string): string => `${safeKey(key)}.chunks`;
  const chunkKey = (key: string, index: number): string =>
    `${safeKey(key)}.${index}`;

  const countOf = async (key: string): Promise<number> => {
    const raw = await store.getItemAsync(countKey(key));
    const count = raw === null ? 0 : Number(raw);
    return Number.isInteger(count) && count > 0 ? count : 0;
  };

  const removeChunks = async (key: string, from: number): Promise<void> => {
    const count = await countOf(key);
    const deletes: Promise<void>[] = [];
    for (let index = from; index < count; index += 1)
      deletes.push(store.deleteItemAsync(chunkKey(key, index)));
    await Promise.all(deletes);
  };

  return {
    async getItem(key) {
      const count = await countOf(key);
      if (count === 0) return null;
      const chunks = await Promise.all(
        Array.from({ length: count }, (_, index) =>
          store.getItemAsync(chunkKey(key, index)),
        ),
      );
      if (chunks.some((chunk) => chunk === null)) return null;
      return chunks.join("");
    },
    async setItem(key, value) {
      const chunks: string[] = [];
      for (let start = 0; start < value.length; start += size)
        chunks.push(value.slice(start, start + size));
      if (chunks.length === 0) chunks.push("");
      await Promise.all(
        chunks.map((chunk, index) =>
          store.setItemAsync(chunkKey(key, index), chunk),
        ),
      );
      await removeChunks(key, chunks.length);
      await store.setItemAsync(countKey(key), String(chunks.length));
    },
    async removeItem(key) {
      await removeChunks(key, 0);
      await store.deleteItemAsync(countKey(key));
    },
  };
}
