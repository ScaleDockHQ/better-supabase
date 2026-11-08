import type { BucketConfig, ClientBucket } from "../bucket.ts";

import { createBucketBase } from "../client-bucket.ts";

/**
 * A bucket definition without SQL, policy checks, `config.toml` or the admin
 * API, for code that ships to the browser. It takes the same config as
 * `defineBucket` from `better-supabase/storage`, so the server and the CLI can
 * keep using that one; `Bucket` there is assignable to `ClientBucket` here.
 */
export function defineBucket<
  const P extends string,
  const Id extends string = string,
  const V extends string = never,
>(config: BucketConfig<P, Id, V>): ClientBucket<P, Id, V> {
  return createBucketBase(config, String).bucket;
}
