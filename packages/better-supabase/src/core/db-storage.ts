import type { StorageApi } from "../storage/storage-api.ts";

import { isStorageApi } from "../storage/storage-api.ts";
import { isRecord } from "./guards.ts";

/** What a `Db` was connected to: its client, and the `storage` option. */
export interface DbSource {
  readonly client: unknown;
  readonly storage: StorageApi | undefined;
}

/**
 * A supabase-js client builds a new storage client on each read of `storage`,
 * so it is read once per connection.
 */
const clientStorage = new WeakMap<DbSource, StorageApi>();

export function storageOf(source: DbSource): StorageApi {
  if (source.storage) {
    return source.storage;
  }

  const cached = clientStorage.get(source);

  if (cached) {
    return cached;
  }

  const client = source.client;
  const storage = isRecord(client) ? client["storage"] : undefined;

  if (isStorageApi(storage)) {
    clientStorage.set(source, storage);

    return storage;
  }

  throw new TypeError(
    "better-supabase: db.$storage needs a client with storage, or connect(executor, context, { storage })",
  );
}
