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
 * Where a value's chunks live: `<key>.<n>` (slot `""`) or `<key>.<n>b`
 * (slot `"b"`). A write fills the slot the pointer does not name, so the
 * pointer only ever names complete chunks.
 */
type Slot = "" | "b";

/** `<count>` or `<count>b` in `<key>.chunks`. */
const POINTER = /^([1-9]\d*)(b?)$/;

/**
 * Supabase Auth storage on the device keychain (`expo-secure-store`),
 * split into chunks so sessions above the platform's value size fit.
 * Operations on one key run one at a time, and a write moves the pointer
 * only after every chunk is stored, so a reader never joins chunks of two
 * values and a write that fails part way keeps the previous value.
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
  const chunkKey = (key: string, slot: Slot, index: number): string =>
    `${safeKey(key)}.${index}${slot}`;

  const pointerOf = async (
    key: string,
  ): Promise<{ readonly count: number; readonly slot: Slot }> => {
    const raw = await store.getItemAsync(countKey(key));
    const match = raw === null ? null : POINTER.exec(raw);
    return match
      ? { count: Number(match[1]), slot: match[2] === "b" ? "b" : "" }
      : { count: 0, slot: "b" };
  };

  const removeChunks = async (
    key: string,
    slot: Slot,
    count: number,
  ): Promise<void> => {
    await Promise.all(
      Array.from({ length: count }, (_, index) =>
        store.deleteItemAsync(chunkKey(key, slot, index)),
      ),
    );
  };

  const queues = new Map<string, Promise<void>>();
  /** Runs `task` after every earlier operation on `key` settled. */
  const serial = <T>(key: string, task: () => Promise<T>): Promise<T> => {
    const run = (queues.get(key) ?? Promise.resolve()).then(task);
    const settled = run.then(
      () => undefined,
      () => undefined,
    );
    queues.set(key, settled);
    void settled.then(() => {
      if (queues.get(key) === settled) queues.delete(key);
    });
    return run;
  };

  return {
    getItem: (key) =>
      serial(key, async () => {
        const { count, slot } = await pointerOf(key);
        if (count === 0) return null;
        const chunks = await Promise.all(
          Array.from({ length: count }, (_, index) =>
            store.getItemAsync(chunkKey(key, slot, index)),
          ),
        );
        if (chunks.some((chunk) => chunk === null)) return null;
        return chunks.join("");
      }),
    setItem: (key, value) =>
      serial(key, async () => {
        const chunks: string[] = [];
        for (let start = 0; start < value.length; start += size)
          chunks.push(value.slice(start, start + size));
        if (chunks.length === 0) chunks.push("");
        const previous = await pointerOf(key);
        const slot: Slot = previous.slot === "b" ? "" : "b";
        await Promise.all(
          chunks.map((chunk, index) =>
            store.setItemAsync(chunkKey(key, slot, index), chunk),
          ),
        );
        await store.setItemAsync(countKey(key), `${chunks.length}${slot}`);
        await removeChunks(key, previous.slot, previous.count);
      }),
    removeItem: (key) =>
      serial(key, async () => {
        const previous = await pointerOf(key);
        await store.deleteItemAsync(countKey(key));
        await removeChunks(key, previous.slot, previous.count);
      }),
  };
}
