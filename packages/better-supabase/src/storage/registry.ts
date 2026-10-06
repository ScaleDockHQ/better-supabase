import type {
  Bucket,
  BucketClient,
  BucketConnectOptions,
  StorageClient,
} from "./bucket.ts";
import type { StoragePath } from "./path.ts";

import { dbError } from "../core/errors.ts";
import { err, ok, type Result } from "../core/result.ts";

/** Any bucket definition from `defineBucket` or a preset. */
export type AnyBucket = Bucket<string>;

export type BucketMap = Readonly<Record<string, AnyBucket>>;

/** The bucket ids of a registry's buckets. */
export type BucketIdOf<B extends BucketMap> = B[keyof B]["id"];

/** The bucket of a registry whose id is `I`. */
export type BucketWithId<B extends BucketMap, I extends string> = Extract<
  B[keyof B],
  { readonly id: I }
>;

/** A stored object as rows keep it: the bucket id and the object path. */
export interface StoredRef {
  /** The bucket id, e.g. a `bucket_id` column. */
  readonly bucket: string;
  readonly path: string;
}

/** A stored reference whose bucket is registered and whose path matches one of its templates. */
export interface ResolvedRef<B extends BucketMap> {
  readonly bucket: B[keyof B];
  readonly path: StoragePath<BucketIdOf<B>>;
}

/** A resolved reference with a client of its bucket. */
export interface ConnectedRef<B extends BucketMap> extends ResolvedRef<B> {
  readonly storage: BucketClient<string, BucketIdOf<B>>;
}

export interface Buckets<B extends BucketMap> {
  /** The bucket definitions, by the names given. */
  readonly buckets: B;
  /** Every registered bucket id, in the order given. */
  readonly ids: readonly BucketIdOf<B>[];
  /** Whether `id` names a registered bucket. */
  has(id: string): id is BucketIdOf<B>;
  /** The bucket with this id, or `invalid_input` for an id no bucket has. */
  byId<I extends BucketIdOf<B>>(id: I): Result<BucketWithId<B, I>>;
  byId(id: string): Result<B[keyof B]>;
  /**
   * Checks a stored `{ bucket, path }`: the bucket must be registered and the
   * path must match one of its templates. Either failure is `invalid_input`.
   */
  resolve(ref: StoredRef): Result<ResolvedRef<B>>;
  /**
   * `resolve`, then `connect` the bucket and check the path with the
   * connected client, so a bucket with `tenant` also refuses another
   * tenant's path (`forbidden`). No request is made.
   */
  connectStored(
    client: StorageClient,
    ref: StoredRef,
    options?: BucketConnectOptions,
  ): Result<ConnectedRef<B>>;
}

/**
 * A registry of bucket definitions by id, for rows that store a bucket id
 * next to an object path (files, attachments, sources). An id no bucket
 * has, and a path outside the bucket's templates, are errors, never a
 * fallback bucket.
 *
 * ```ts
 * export const buckets = defineBuckets({ files, attachments, logos });
 *
 * const ref = buckets.connectStored(supabase, {
 *   bucket: row.bucketId,
 *   path: row.path,
 * }, { context: db.$context });
 * if (ref.ok) await ref.data.storage.signedUrl(ref.data.path);
 * ```
 */
export function defineBuckets<const B extends BucketMap>(
  buckets: B,
): Buckets<B> {
  const byId = new Map<string, B[keyof B]>();
  for (const [name, bucket] of Object.entries(buckets)) {
    const existing = byId.get(bucket.id);
    if (existing !== undefined) {
      throw new TypeError(
        `defineBuckets: "${name}" reuses the bucket id "${bucket.id}"`,
      );
    }
    // SAFETY: the value comes from the entries of B.
    byId.set(bucket.id, bucket as B[keyof B]);
  }
  const lookup = (id: string): Result<B[keyof B]> => {
    const bucket = byId.get(id);
    return bucket === undefined
      ? err(dbError("invalid_input", `Bucket "${id}" is not registered`))
      : ok(bucket);
  };
  const resolve = (ref: StoredRef): Result<ResolvedRef<B>> => {
    const found = lookup(ref.bucket);
    if (!found.ok) return found;
    const bucket = found.data;
    if (bucket.match(ref.path) === null) {
      return err(
        dbError(
          "invalid_input",
          `Path "${ref.path}" does not match "${bucket.templates.join('" or "')}"`,
          { table: bucket.id },
        ),
      );
    }
    // SAFETY: match accepted the path for this bucket above.
    return ok({ bucket, path: ref.path as StoragePath<BucketIdOf<B>> });
  };
  return {
    buckets,
    // SAFETY: the map keys are the ids of B's buckets.
    ids: [...byId.keys()] as BucketIdOf<B>[],
    has: (id): id is BucketIdOf<B> => byId.has(id),
    // SAFETY: lookup returns the bucket registered under the id, so for a
    // known id I it is the bucket whose id is I.
    byId: lookup as Buckets<B>["byId"],
    resolve,
    connectStored(client, ref, options) {
      const resolved = resolve(ref);
      if (!resolved.ok) return resolved;
      const { bucket } = resolved.data;
      const storage: BucketClient<string, BucketIdOf<B>> = bucket.connect(
        client,
        options,
      );
      const path = storage.path(ref.path);
      return path.ok ? ok({ bucket, storage, path: path.data }) : path;
    },
  };
}
