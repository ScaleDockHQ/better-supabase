declare const bucketOf: unique symbol;

/**
 * An object path in bucket `B`, e.g. `org-1/cust-1/logo/3.webp`. Returned by
 * `bucket.path()` and `upload()`, and the type of columns listed in the
 * `storagePaths` config. Store paths, not URLs: signed URLs expire and public
 * URLs pin the project host.
 */
export type StoragePath<B extends string = string> = string & {
  readonly [bucketOf]: B;
};

/** A plain string or a `StoragePath` of bucket `B`; paths of other buckets are rejected. */
export type PathIn<B extends string> = string & {
  readonly [bucketOf]?: B;
};
