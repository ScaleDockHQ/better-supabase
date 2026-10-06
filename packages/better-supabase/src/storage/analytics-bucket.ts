import type { SupabaseClient } from "@supabase/supabase-js";

import type { StorageClient } from "./bucket.ts";

import { AsyncResult, err, ok } from "../core/result.ts";
import { fromStorageError } from "./errors.ts";

/** The Iceberg REST catalog of an analytics bucket, from `storage.analytics.from(id)`. */
export type AnalyticsCatalog = ReturnType<
  SupabaseClient["storage"]["analytics"]["from"]
>;

export interface AnalyticsBucketClient {
  /** Creates the bucket when it is missing. Needs the secret key. */
  apply(): AsyncResult<{ readonly created: boolean }>;
  /** The bucket's Iceberg catalog: namespaces and tables, each call returning `{ data, error }`. */
  catalog(): AnalyticsCatalog;
}

export interface AnalyticsBucket<Id extends string> {
  readonly id: Id;
  connect(client: StorageClient): AnalyticsBucketClient;
}

/**
 * A Storage analytics bucket: Apache Iceberg tables that query engines read
 * through the Iceberg REST catalog.
 *
 * ```ts
 * export const events = defineAnalyticsBucket({ id: "events" });
 * await events.connect(admin).apply().orThrow();
 * ```
 */
export function defineAnalyticsBucket<const Id extends string>(config: {
  readonly id: Id;
}): AnalyticsBucket<Id> {
  return {
    id: config.id,
    connect: (client) => ({
      apply: () =>
        AsyncResult.from<{ readonly created: boolean }>(async () => {
          const analytics = client.storage.analytics;
          try {
            const listed = await analytics.listBuckets({ search: config.id });
            if (listed.error)
              return err(fromStorageError(listed.error, config.id));
            if (listed.data.some((bucket) => bucket.name === config.id))
              return ok({ created: false });
            const made = await analytics.createBucket(config.id);
            if (made.error) return err(fromStorageError(made.error, config.id));
            return ok({ created: true });
          } catch (cause) {
            return err(fromStorageError(cause, config.id));
          }
        }),
      catalog: () => client.storage.analytics.from(config.id),
    }),
  };
}
