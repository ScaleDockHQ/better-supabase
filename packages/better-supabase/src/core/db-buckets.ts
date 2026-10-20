import type { Bucket, BucketClient } from "../storage/bucket.ts";

/** Buckets registered with `betterSupabase.buckets()`, by key. */
export type BucketRegistry = Readonly<
  // oxlint-disable-next-line typescript/no-explicit-any -- Bucket is invariant in its template and id parameters.
  Record<string, Bucket<any, any>>
>;

/** `db.$buckets`: one connected client per registered bucket. */
export type BucketsHelper<B> = unknown extends B
  ? unknown
  : {
      /**
       * The registered buckets, connected to `db.$storage`. They run as the
       * same caller as the `Db` and keep the tenant guard. Created on first
       * read and reused for this `Db`.
       */
      readonly $buckets: {
        readonly [K in keyof B]: B[K] extends Bucket<infer P, infer Id>
          ? BucketClient<P, Id>
          : never;
      };
    };
