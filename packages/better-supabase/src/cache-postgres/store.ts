import type {
  PostgresCacheSource,
  PostgresCacheStore,
  PostgresCacheStoreOptions,
  PostgresCacheTables,
} from "./store-core.ts";

import { postgresCacheNames } from "./names.ts";
import { sqlBackend } from "./sql-backend.ts";
import { createCacheStore, isStore, restBackend } from "./store-core.ts";

export type {
  CacheLookup,
  PostgresCacheSource,
  PostgresCacheSqlClient,
  PostgresCacheStore,
  PostgresCacheStoreOptions,
  PostgresCacheTables,
  StoredCacheEntry,
  TagState,
} from "./store-core.ts";

export { decodeBase64, encodeBase64 } from "./store-core.ts";

/** The store of a handler's or provider's options. */
export function storeOf(
  options: PostgresCacheTables & PostgresCacheSource,
): PostgresCacheStore {
  if (options.transport !== undefined) {
    return postgresCacheStore({ ...options, transport: options.transport });
  }

  return isStore(options.client)
    ? options.client
    : postgresCacheStore({ ...options, client: options.client });
}

/**
 * Entries and tag states in two Postgres tables (`postgresCacheSql()` creates
 * them), so every instance reads what another wrote and a tag one expires is
 * expired on all. A read and a tag mark are one function call each; without the
 * functions the store falls back to the tables. Methods return a `Result`; none
 * throws.
 */
export function postgresCacheStore(
  options: PostgresCacheStoreOptions,
): PostgresCacheStore {
  const names = postgresCacheNames(options);

  return createCacheStore(
    options.transport === undefined
      ? restBackend(options.client, names)
      : sqlBackend(options.transport.postgres, names),
    options,
  );
}
