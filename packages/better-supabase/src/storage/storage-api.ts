import type { UploadBody } from "./bucket.ts";

/** A failed Storage call's `error`, as supabase-js returns it (`StorageApiError`, `StorageUnknownError`). */
export interface StorageFailure {
  readonly name: string;
  readonly message: string;
  readonly status?: number | undefined;
  readonly statusCode?: string | undefined;
  /** The Storage error code, such as `NoSuchKey` or `AccessDenied`. */
  readonly code?: string | undefined;
}

/** What a supabase-js Storage call resolves to: `data` or `error`, never both. */
export type StorageResponse<T> =
  | { readonly data: T; readonly error: null }
  | { readonly data: null; readonly error: StorageFailure };

export interface StorageTransform {
  readonly width?: number;
  readonly height?: number;
  readonly resize?: "cover" | "contain" | "fill";
  readonly quality?: number;
  readonly format?: "origin";
}

export interface StorageUrlOptions {
  readonly download?: string | boolean;
  readonly transform?: StorageTransform;
  readonly cacheNonce?: string;
  readonly versionId?: string;
}

export interface StorageDownloadOptions {
  readonly transform?: StorageTransform;
  readonly cacheNonce?: string;
  readonly versionId?: string;
}

export interface StorageFetchParameters {
  readonly signal?: AbortSignal;
  readonly cache?:
    | "default"
    | "no-store"
    | "reload"
    | "no-cache"
    | "force-cache"
    | "only-if-cached";
}

export interface StorageFileOptions {
  readonly cacheControl?: string;
  readonly contentType?: string;
  readonly upsert?: boolean;
  readonly duplex?: string;
  readonly metadata?: Readonly<Record<string, unknown>>;
  readonly headers?: Readonly<Record<string, string>>;
}

export interface StorageDestinationOptions {
  readonly destinationBucket?: string;
  readonly sourceVersionId?: string;
}

/** `list(prefix, options)`: one folder level, folders first when sorted by name. */
export interface StorageSearchOptions {
  /** Defaults to 100. */
  readonly limit?: number;
  readonly offset?: number;
  /** Defaults to `{ column: "name", order: "asc" }`. */
  readonly sortBy?: { readonly column?: string; readonly order?: string };
  /** Entries whose name starts with this text, ignoring case. */
  readonly search?: string;
  readonly noncurrentVersions?: "exclude" | "include" | "only";
  readonly deleteMarkers?: "exclude" | "include" | "only";
  readonly exactMatch?: boolean;
}

export interface StorageSearchV2Options {
  /** Defaults to 1000, the most one page returns. */
  readonly limit?: number;
  readonly prefix?: string;
  /** `nextCursor` of the previous page. */
  readonly cursor?: string;
  /** Group the objects below the next `/` into folders. */
  readonly with_delimiter?: boolean;
  readonly sortBy?: {
    readonly column: "name" | "updated_at" | "created_at";
    readonly order?: "asc" | "desc";
  };
  readonly noncurrentVersions?: "exclude" | "include" | "only";
  readonly deleteMarkers?: "exclude" | "include" | "only";
  readonly exactMatch?: boolean;
}

/** An entry of `list`: a file, or a folder when `id` is `null`. */
export interface StorageListEntry {
  readonly name: string;
  readonly id: string | null;
  readonly updated_at: string | null;
  readonly created_at: string | null;
  readonly last_accessed_at?: string | null;
  readonly metadata: Readonly<Record<string, unknown>> | null;
}

export interface StorageListV2Object {
  readonly name: string;
  readonly key?: string;
  readonly id: string;
  readonly updated_at: string;
  readonly created_at: string;
  readonly last_accessed_at?: string;
  readonly metadata: Readonly<Record<string, unknown>> | null;
  readonly version?: string;
  readonly archived_at?: string | null;
  readonly is_delete_marker?: boolean;
  readonly is_versioned?: boolean;
}

export interface StorageListV2Result {
  readonly hasNext: boolean;
  readonly nextCursor?: string;
  readonly folders: readonly {
    readonly name: string;
    readonly key?: string;
  }[];
  readonly objects: readonly StorageListV2Object[];
}

/** `info(path)`, in camelCase as supabase-js returns it. */
export interface StorageObjectInfo {
  readonly id: string;
  readonly name: string;
  readonly version: string;
  readonly bucketId: string;
  readonly createdAt: string;
  readonly size?: number;
  readonly contentType?: string;
  readonly cacheControl?: string;
  readonly etag?: string;
  readonly lastModified?: string;
  readonly metadata?: Readonly<Record<string, unknown>>;
  readonly updatedAt?: string;
  readonly archivedAt?: string | null;
  readonly isDeleteMarker?: boolean;
  readonly isVersioned?: boolean;
}

export interface StorageSignedUrlEntry {
  readonly error: string | null;
  readonly path: string | null;
  readonly signedUrl: string | null;
}

export type StorageRemoveEntry =
  | string
  | { readonly path: string; readonly versionId: string };

/**
 * One bucket's file API: the methods of supabase-js
 * `supabase.storage.from(bucket)` that bucket clients and blocks call,
 * typed structurally so another implementation (such as `supportStorage`)
 * can stand in for it.
 */
export interface StorageBucketApi {
  upload(
    path: string,
    body: UploadBody,
    options?: StorageFileOptions,
  ): PromiseLike<StorageResponse<{ readonly path: string }>>;
  update(
    path: string,
    body: UploadBody,
    options?: StorageFileOptions,
  ): PromiseLike<StorageResponse<{ readonly path: string }>>;
  createSignedUploadUrl(
    path: string,
    options?: { upsert: boolean },
  ): PromiseLike<
    StorageResponse<{
      readonly signedUrl: string;
      readonly token: string;
      readonly path: string;
    }>
  >;
  uploadToSignedUrl(
    path: string,
    token: string,
    body: UploadBody,
    options?: StorageFileOptions,
  ): PromiseLike<StorageResponse<{ readonly path: string }>>;
  download(
    path: string,
    options?: StorageDownloadOptions,
    parameters?: StorageFetchParameters,
  ): PromiseLike<StorageResponse<Blob>>;
  info(
    path: string,
    options?: { versionId?: string },
  ): PromiseLike<StorageResponse<StorageObjectInfo>>;
  /** `data` is `false` with an `error` when Storage answers 400 or 404. */
  exists(
    path: string,
  ): PromiseLike<
    | { readonly data: boolean; readonly error: null }
    | { readonly data: boolean; readonly error: StorageFailure }
  >;
  createSignedUrl(
    path: string,
    expiresIn: number,
    options?: StorageUrlOptions,
  ): PromiseLike<StorageResponse<{ readonly signedUrl: string }>>;
  createSignedUrls(
    paths: string[],
    expiresIn: number,
    options?: { download?: string | boolean; cacheNonce?: string },
  ): PromiseLike<StorageResponse<readonly StorageSignedUrlEntry[]>>;
  getPublicUrl(
    path: string,
    options?: StorageUrlOptions,
  ): { readonly data: { readonly publicUrl: string } };
  remove(
    paths: StorageRemoveEntry[],
  ): PromiseLike<StorageResponse<readonly StorageListEntry[]>>;
  copy(
    from: string,
    to: string,
    options?: StorageDestinationOptions,
  ): PromiseLike<StorageResponse<{ readonly path: string }>>;
  move(
    from: string,
    to: string,
    options?: StorageDestinationOptions,
  ): PromiseLike<StorageResponse<{ readonly message: string }>>;
  purgeCache(
    path: string,
    options?: { transformations?: true },
    parameters?: StorageFetchParameters,
  ): PromiseLike<StorageResponse<{ readonly message: string }>>;
  list(
    path?: string,
    options?: StorageSearchOptions,
    parameters?: StorageFetchParameters,
  ): PromiseLike<StorageResponse<readonly StorageListEntry[]>>;
  listV2(
    options?: StorageSearchV2Options,
    parameters?: StorageFetchParameters,
  ): PromiseLike<StorageResponse<StorageListV2Result>>;
}

/** Storage's file API: `supabase.storage`, or anything with the same `from(bucket)`. */
export interface StorageApi {
  from(bucket: string): StorageBucketApi;
}

/** What `bucket.connect()` takes: a `StorageApi`, or a client that carries one as `storage` (a supabase-js client). */
export type StorageClient = StorageApi | { readonly storage: StorageApi };

/** The `StorageApi` of a client, or the client itself. */
export function storageApiOf(client: StorageClient): StorageApi {
  return "storage" in client ? client.storage : client;
}
