import type { StorageApi } from "../storage/storage-api.ts";

import { isStorageApi } from "../storage/storage-api.ts";
import { isRecord } from "./guards.ts";

/** What a `Db` was connected to: its client, and the `storage` option. */
export interface DbSource {
  readonly client: unknown;
  readonly storage: StorageApi | undefined;
}

export function storageOf(source: DbSource): StorageApi {
  if (source.storage) {
    return source.storage;
  }

  const client = source.client;
  const storage = isRecord(client) ? client["storage"] : undefined;

  if (isStorageApi(storage)) {
    return storage;
  }

  throw new TypeError(
    "better-supabase: db.$storage needs a client with storage, or connect(executor, context, { storage })",
  );
}
