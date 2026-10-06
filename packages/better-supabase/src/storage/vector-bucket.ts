import type { StorageClient } from "./bucket.ts";

import { type DbError, dbError } from "../core/errors.ts";
import { AsyncResult, err, ok, type Result } from "../core/result.ts";
import { fromStorageError } from "./errors.ts";

export type VectorDistance = "cosine" | "euclidean" | "dotproduct";

export interface VectorIndexConfig {
  /** Number of values in every vector, e.g. 1536 for `text-embedding-3-small`. */
  readonly dimension: number;
  /** Defaults to `cosine`. */
  readonly distanceMetric?: VectorDistance;
  /** Metadata keys stored with each vector but not usable in `filter`. */
  readonly nonFilterableMetadataKeys?: readonly string[];
}

export interface VectorBucketConfig<
  Id extends string,
  I extends Readonly<Record<string, VectorIndexConfig>>,
> {
  readonly id: Id;
  readonly indexes: I;
}

export type VectorMetadata = Readonly<Record<string, unknown>>;

export interface VectorRecord<M extends VectorMetadata = VectorMetadata> {
  readonly key: string;
  readonly vector: readonly number[];
  readonly metadata?: M;
}

export interface VectorHit<M extends VectorMetadata = VectorMetadata> {
  readonly key: string;
  /** Set by `query()`: smaller is closer for every metric. */
  readonly distance?: number;
  readonly metadata?: M;
  readonly vector?: readonly number[];
}

export interface VectorQueryOptions {
  /** Number of matches, defaults to 10. */
  readonly topK?: number;
  /** A metadata filter, e.g. `{ organizationId: "o1" }` or `{ year: { $gte: 2024 } }`. */
  readonly filter?: VectorMetadata;
  /** Return each match's metadata. Defaults to `true`. */
  readonly metadata?: boolean;
}

export interface VectorIndexClient<M extends VectorMetadata = VectorMetadata> {
  readonly name: string;
  readonly dimension: number;
  /** Inserts or replaces vectors by key, in batches of 500. */
  put(records: readonly VectorRecord<M>[]): AsyncResult<number>;
  /** The nearest vectors, closest first. */
  query(
    vector: readonly number[],
    options?: VectorQueryOptions,
  ): AsyncResult<readonly VectorHit<M>[]>;
  /** Vectors by key; missing keys are left out. */
  get(
    keys: readonly string[],
    options?: { readonly vector?: boolean },
  ): AsyncResult<readonly VectorHit<M>[]>;
  remove(keys: readonly string[]): AsyncResult<readonly string[]>;
}

export interface VectorBucketClient<I extends string> {
  /** Creates the bucket and any missing index. An index with another dimension or metric is a `conflict`. */
  apply(): AsyncResult<{ readonly created: readonly string[] }>;
  index<M extends VectorMetadata = VectorMetadata>(
    name: I,
  ): VectorIndexClient<M>;
}

export interface VectorBucket<
  Id extends string,
  I extends Readonly<Record<string, VectorIndexConfig>>,
> {
  readonly id: Id;
  readonly indexes: I;
  connect(client: StorageClient): VectorBucketClient<keyof I & string>;
}

const PUT_BATCH = 500;
const GET_BATCH = 100;

function chunks<T>(items: readonly T[], size: number): T[][] {
  const out: T[][] = [];
  for (let index = 0; index < items.length; index += size)
    out.push(items.slice(index, index + size));
  return out;
}

const metricOf = (config: VectorIndexConfig): VectorDistance =>
  config.distanceMetric ?? "cosine";

/**
 * A Storage vector bucket with typed indexes. Storage keeps the vectors
 * outside Postgres; use the `vector-search` module for pgvector in a table.
 *
 * ```ts
 * export const embeddings = defineVectorBucket({
 *   id: "embeddings",
 *   indexes: { documents: { dimension: 1536 } },
 * });
 * const docs = embeddings.connect(admin).index("documents");
 * await docs.put([{ key: doc.id, vector, metadata: { organizationId } }]);
 * ```
 */
export function defineVectorBucket<
  const Id extends string,
  const I extends Readonly<Record<string, VectorIndexConfig>>,
>(config: VectorBucketConfig<Id, I>): VectorBucket<Id, I> {
  for (const [name, index] of Object.entries(config.indexes)) {
    if (!Number.isInteger(index.dimension) || index.dimension < 1)
      throw new TypeError(
        `defineVectorBucket("${config.id}"): index "${name}" needs a whole, positive dimension`,
      );
  }
  return {
    id: config.id,
    indexes: config.indexes,
    connect: (client) => connectVectorBucket(config, client),
  };
}

function connectVectorBucket<I extends string>(
  config: VectorBucketConfig<string, Readonly<Record<I, VectorIndexConfig>>>,
  client: StorageClient,
): VectorBucketClient<I> {
  const vectors = () => client.storage.vectors;
  const scope = () => vectors().from(config.id);
  const failure = (raw: unknown): DbError => fromStorageError(raw, config.id);
  const attempt = <T>(fn: () => Promise<Result<T>>): AsyncResult<T> =>
    AsyncResult.from(async () => {
      try {
        return await fn();
      } catch (cause) {
        return err(failure(cause));
      }
    });

  return {
    apply: () =>
      attempt(async () => {
        const created: string[] = [];
        const found = await vectors().getBucket(config.id);
        if (found.error) {
          if (failure(found.error).kind !== "not_found")
            return err(failure(found.error));
          const made = await vectors().createBucket(config.id);
          if (made.error) return err(failure(made.error));
        }
        const entries: [string, VectorIndexConfig][] = Object.entries(
          config.indexes,
        );
        for (const [name, index] of entries) {
          const existing = await scope().getIndex(name);
          if (existing.data) {
            const actual = existing.data.index;
            if (
              actual.dimension !== index.dimension ||
              actual.distanceMetric !== metricOf(index)
            )
              return err(
                dbError(
                  "conflict",
                  `Vector index "${name}" has dimension ${String(actual.dimension)} and metric ${actual.distanceMetric}, not ${String(index.dimension)} and ${metricOf(index)}`,
                  { table: config.id },
                ),
              );
            continue;
          }
          if (failure(existing.error).kind !== "not_found")
            return err(failure(existing.error));
          const made = await scope().createIndex({
            indexName: name,
            dataType: "float32",
            dimension: index.dimension,
            distanceMetric: metricOf(index),
            ...(index.nonFilterableMetadataKeys
              ? {
                  metadataConfiguration: {
                    nonFilterableMetadataKeys: [
                      ...index.nonFilterableMetadataKeys,
                    ],
                  },
                }
              : {}),
          });
          if (made.error) return err(failure(made.error));
          created.push(name);
        }
        return ok({ created });
      }),
    index<M extends VectorMetadata>(name: I): VectorIndexClient<M> {
      const settings: VectorIndexConfig = config.indexes[name];
      const api = () => scope().index(name);
      const checkDimension = (
        vector: readonly number[],
        key?: string,
      ): DbError | undefined =>
        vector.length === settings.dimension
          ? undefined
          : dbError(
              "invalid_input",
              `${key === undefined ? "The query vector" : `Vector "${key}"`} has ${String(vector.length)} values; index "${name}" takes ${String(settings.dimension)}`,
              { table: config.id },
            );
      // SAFETY: Storage returns the metadata that `put` stored for these keys.
      const hit = (match: {
        key: string;
        distance?: number;
        metadata?: Record<string, unknown>;
        data?: { float32: number[] };
      }): VectorHit<M> => ({
        key: match.key,
        ...(match.distance === undefined ? {} : { distance: match.distance }),
        ...(match.metadata === undefined
          ? {}
          : { metadata: match.metadata as M }),
        ...(match.data ? { vector: match.data.float32 } : {}),
      });
      return {
        name,
        dimension: settings.dimension,
        put: (records) =>
          attempt(async () => {
            for (const record of records) {
              const problem = checkDimension(record.vector, record.key);
              if (problem) return err(problem);
            }
            for (const batch of chunks(records, PUT_BATCH)) {
              const put = await api().putVectors({
                vectors: batch.map((record) => ({
                  key: record.key,
                  data: { float32: [...record.vector] },
                  ...(record.metadata
                    ? { metadata: { ...record.metadata } }
                    : {}),
                })),
              });
              if (put.error) return err(failure(put.error));
            }
            return ok(records.length);
          }),
        query: (vector, options = {}) =>
          attempt(async () => {
            const problem = checkDimension(vector);
            if (problem) return err(problem);
            const found = await api().queryVectors({
              queryVector: { float32: [...vector] },
              topK: options.topK ?? 10,
              returnDistance: true,
              returnMetadata: options.metadata ?? true,
              ...(options.filter ? { filter: { ...options.filter } } : {}),
            });
            if (found.error) return err(failure(found.error));
            return ok(found.data.vectors.map(hit));
          }),
        get: (keys, options = {}) =>
          attempt(async () => {
            const out: VectorHit<M>[] = [];
            for (const batch of chunks(keys, GET_BATCH)) {
              const found = await api().getVectors({
                keys: batch,
                returnMetadata: true,
                returnData: options.vector ?? false,
              });
              if (found.error) return err(failure(found.error));
              out.push(...found.data.vectors.map(hit));
            }
            return ok(out);
          }),
        remove: (keys) =>
          attempt(async () => {
            for (const batch of chunks(keys, PUT_BATCH)) {
              const removed = await api().deleteVectors({ keys: batch });
              if (removed.error) return err(failure(removed.error));
            }
            return ok(keys);
          }),
      };
    },
  };
}
