import type { DbError } from "../core/errors.ts";
import type { Result } from "../core/result.ts";
import type { TransformOptions } from "./bucket.ts";

import { dbError } from "../core/errors.ts";
import { portOf } from "../core/port.ts";
import { AsyncResult, err, ok, toDbError } from "../core/result.ts";
import { fromStorageError } from "./errors.ts";

/** The bytes a `FileStore` takes. */
export type FileBody = Blob | ArrayBuffer | Uint8Array;

/** What `head` reads about a stored file. */
export interface FileHead {
  /** Bytes, as the store counted them. */
  readonly size: number;
  /** The type the store keeps with the file. */
  readonly contentType: string;
}

/**
 * Where a browser sends a file's bytes: `method` to `url` with `headers` and
 * the file as the body.
 */
export interface SignedUpload {
  readonly url: string;
  readonly method: "PUT" | "POST";
  readonly headers: Readonly<Record<string, string>>;
  /**
   * Supabase's upload token, for `uploadToSignedUrl(path, token, file)`;
   * `undefined` for a store without one.
   */
  readonly token?: string;
}

/**
 * Where the `attachments` and `drive` blocks keep the bytes of files: Supabase
 * Storage by default (`supabaseFileStore`), or another store such as Vercel
 * Blob (`vercelBlobStore`). Postgres keeps the records and decides who may
 * upload, read and delete; the store only holds bytes under `bucket` and
 * `path`. Versioned: a breaking change to this contract ships a new
 * `apiVersion`. Methods never throw; they answer `DbError`s, with `not_found`
 * for a file the store doesn't have.
 */
export interface FileStore {
  readonly apiVersion: 1;
  /** Such as `supabase` or `vercel-blob`. */
  readonly name: string;
  /**
   * Stores `body` at `path`. Without `upsert`, a file already at `path` is an
   * error and stays as it was.
   */
  put(
    bucket: string,
    path: string,
    body: FileBody,
    options?: { readonly contentType?: string; readonly upsert?: boolean },
  ): AsyncResult<void>;
  /** The file's bytes, typed with its stored content type. */
  get(bucket: string, path: string): AsyncResult<Blob>;
  /** Deletes the files; a path the store doesn't have is not an error. */
  delete(bucket: string, paths: readonly string[]): AsyncResult<void>;
  /**
   * A URL that reads the file for `expiresIn` seconds. `download` asks the
   * browser to save the file, under that name when it is a string.
   */
  signedUrl(
    bucket: string,
    path: string,
    options: {
      readonly expiresIn: number;
      readonly download?: string | boolean;
    },
  ): AsyncResult<string>;
  /**
   * The file's size and type, or `undefined` when the store doesn't have it.
   * `confirm` reads it for a store Postgres can't see, so it never trusts what
   * a browser says about the upload.
   */
  head?(bucket: string, path: string): AsyncResult<FileHead | undefined>;
  /**
   * Where a browser uploads the file at `path`, once Postgres reserved the
   * path. `contentType` and `maxSize` limit the upload where the store can.
   */
  signedUploadUrl?(
    bucket: string,
    path: string,
    options: {
      readonly expiresIn?: number;
      readonly contentType?: string;
      readonly maxSize?: number;
    },
  ): AsyncResult<SignedUpload>;
}

/** Checks the store's `apiVersion` before a block uses it. */
export function fileStoreOf<S extends FileStore>(store: S): S {
  return portOf(`file store "${store.name}"`, "file store", store);
}

interface StorageReply<T> {
  readonly data: T | null;
  readonly error: unknown;
}

/**
 * The `supabase.storage.from(bucket)` methods `supabaseFileStore` calls, typed
 * structurally. Each is optional: an operation whose method the client lacks
 * answers `invalid_request` with hint `STORAGE_CLIENT`.
 */
export interface SupabaseFileBucket {
  upload?(
    path: string,
    body: FileBody,
    options?: { readonly contentType?: string; readonly upsert?: boolean },
  ): PromiseLike<StorageReply<unknown>>;
  download?(path: string): PromiseLike<StorageReply<Blob>>;
  remove?(paths: string[]): PromiseLike<StorageReply<unknown>>;
  createSignedUrl?(
    path: string,
    expiresIn: number,
    options?: { download?: string | boolean; transform?: TransformOptions },
  ): PromiseLike<StorageReply<{ readonly signedUrl: string }>>;
  createSignedUploadUrl?(
    path: string,
  ): PromiseLike<
    StorageReply<{ readonly signedUrl: string; readonly token: string }>
  >;
  /** Used by `head`. */
  info?(
    path: string,
  ): PromiseLike<
    StorageReply<{ readonly size?: number; readonly contentType?: string }>
  >;
  /** Supabase only: the blocks' `publicUrl`. */
  getPublicUrl?(
    path: string,
    options?: { download?: string | boolean; transform?: TransformOptions },
  ): { readonly data: { readonly publicUrl: string } };
  /** Supabase only: the blocks' `uploadFile`. */
  uploadToSignedUrl?(
    path: string,
    token: string,
    body: FileBody,
    options?: { readonly contentType?: string; readonly upsert?: boolean },
  ): PromiseLike<StorageReply<unknown>>;
}

/** `supabase.storage`, typed structurally. */
export interface SupabaseFileStorage {
  from(bucket: string): SupabaseFileBucket;
  /** The claim step of a Storage API such as `supportStorage`. */
  claimSignedUpload?(
    bucket: string,
    path: string,
  ): PromiseLike<{ readonly data: unknown; readonly error: unknown }>;
}

/**
 * The Supabase Storage file store, which keeps `storage` for what only Supabase
 * has: image transforms, public URLs and the upload claim.
 */
export interface SupabaseFileStore<
  S extends SupabaseFileStorage = SupabaseFileStorage,
> extends FileStore {
  readonly name: "supabase";
  readonly storage: S;
}

/** A Storage reply as a result, its error mapped to a `DbError`. */
export function storageReply<T>(
  reply: PromiseLike<StorageReply<T>>,
): AsyncResult<NonNullable<T>> {
  return AsyncResult.from(async () => {
    try {
      const { data, error } = await reply;

      if (error) {
        return err(fromStorageError(error, "storage.objects"));
      }

      if (data === null || data === undefined) {
        return err(dbError("network", "Storage returned no data"));
      }

      return ok(data);
    } catch (cause) {
      return err(fromStorageError(cause, "storage.objects"));
    }
  });
}

const missing = (method: string): AsyncResult<never> =>
  AsyncResult.err(
    dbError("invalid_request", `The storage client has no ${method}`, {
      hint: "STORAGE_CLIENT",
    }),
  );

/**
 * Supabase Storage as a `FileStore`: the caller's `supabase.storage`, so the
 * bucket policies apply. This is what the blocks use when they get `storage`
 * and no `files`.
 */
export function supabaseFileStore<S extends SupabaseFileStorage>(
  storage: S,
): SupabaseFileStore<S> {
  return {
    apiVersion: 1,
    name: "supabase",
    storage,
    put: (bucket, path, body, options) => {
      const target = storage.from(bucket);

      return target.upload
        ? storageReply(target.upload(path, body, options)).map(() => undefined)
        : missing("upload");
    },
    get: (bucket, path) => {
      const target = storage.from(bucket);

      return target.download
        ? storageReply(target.download(path))
        : missing("download");
    },
    delete: (bucket, paths) => {
      if (paths.length === 0) {
        return AsyncResult.ok(undefined);
      }

      const target = storage.from(bucket);

      return target.remove
        ? storageReply(target.remove([...paths])).map(() => undefined)
        : missing("remove");
    },
    signedUrl: (bucket, path, { expiresIn, download }) => {
      const target = storage.from(bucket);

      return target.createSignedUrl
        ? storageReply(
            target.createSignedUrl(
              path,
              expiresIn,
              download === undefined ? undefined : { download },
            ),
          ).map((signed) => signed.signedUrl)
        : missing("createSignedUrl");
    },
    head: (bucket, path) => {
      const target = storage.from(bucket);

      if (!target.info) {
        return missing("info");
      }

      const info = storageReply(target.info(path));

      return AsyncResult.from(async () => {
        const found = await info;

        if (!found.ok) {
          return found.error.kind === "not_found" ? ok(undefined) : found;
        }

        return ok({
          size: found.data.size ?? 0,
          contentType: found.data.contentType ?? "application/octet-stream",
        });
      });
    },
    signedUploadUrl: (bucket, path) => {
      const target = storage.from(bucket);

      return target.createSignedUploadUrl
        ? storageReply(target.createSignedUploadUrl(path)).map(
            (url): SignedUpload => ({
              url: url.signedUrl,
              method: "PUT",
              headers: {},
              token: url.token,
            }),
          )
        : missing("createSignedUploadUrl");
    },
  };
}

/** Whether `store` is Supabase Storage, so the Supabase-only features apply. */
export function isSupabaseFileStore(
  store: FileStore,
): store is SupabaseFileStore {
  return store.name === "supabase" && "storage" in store;
}

type BlobAccess = "public" | "private";

/**
 * The `@vercel/blob` functions `vercelBlobStore` calls, typed structurally:
 * pass `import * as blob from "@vercel/blob"` (`>=2.9.0 <3`).
 */
export interface VercelBlobModule {
  put(
    pathname: string,
    body: Blob | ArrayBuffer,
    options: {
      access: BlobAccess;
      contentType?: string;
      allowOverwrite?: boolean;
      addRandomSuffix?: boolean;
      token?: string;
    },
  ): PromiseLike<unknown>;
  get(
    urlOrPathname: string,
    options: { access: BlobAccess; token?: string },
  ): PromiseLike<{
    readonly stream: ReadableStream<Uint8Array> | null;
    readonly blob: { readonly contentType: string | null };
  } | null>;
  head(
    urlOrPathname: string,
    options?: { token?: string },
  ): PromiseLike<{ readonly size: number; readonly contentType: string }>;
  del(urlOrPathname: string[], options?: { token?: string }): PromiseLike<void>;
  issueSignedToken(options: {
    pathname?: string;
    operations?: ("get" | "head" | "put" | "delete")[];
    validUntil?: number;
    allowedContentTypes?: string[];
    maximumSizeInBytes?: number;
    token?: string;
  }): PromiseLike<{
    readonly clientSigningToken: string;
    readonly delegationToken: string;
  }>;
  presignUrl(
    signedToken: {
      readonly clientSigningToken: string;
      readonly delegationToken: string;
    },
    options: (
      | { operation: "get"; pathname: string; validUntil?: number }
      | {
          operation: "put";
          pathname: string;
          validUntil?: number;
          allowedContentTypes?: string[];
          maximumSizeInBytes?: number;
          allowOverwrite?: boolean;
          addRandomSuffix?: boolean;
        }
    ) & { access: BlobAccess },
  ): PromiseLike<{ readonly presignedUrl: string }>;
  /** Used for `signedUrl` with `download`. */
  getDownloadUrl?(blobUrl: string): string;
}

export interface VercelBlobStoreOptions {
  /**
   * The access every blob gets. Default `private`: a file is read only through
   * a signed URL, as in a private Supabase bucket.
   */
  readonly access?: BlobAccess;
  /** A read-write token. Default: the SDK's `BLOB_READ_WRITE_TOKEN` or OIDC. */
  readonly token?: string;
  /**
   * Put before every pathname, such as `files/`. The pathname is
   * `${prefix}${bucket}/${path}`.
   */
  readonly prefix?: string;
}

/** The `@vercel/blob` error classes by name, with the kind each maps to. */
const BLOB_ERRORS = {
  BlobNotFoundError: "not_found",
  BlobAccessError: "forbidden",
  BlobServiceRateLimited: "rate_limited",
  BlobFileTooLargeError: "invalid_input",
  BlobContentTypeNotAllowedError: "invalid_input",
} as const;

type BlobErrorName = keyof typeof BLOB_ERRORS;

const isBlobErrorName = (name: unknown): name is BlobErrorName =>
  typeof name === "string" && Object.hasOwn(BLOB_ERRORS, name);

/** The fields of a thrown `@vercel/blob` error the mapping reads. */
interface BlobFailure {
  readonly name?: unknown;
  readonly message?: unknown;
  readonly retryAfter?: unknown;
  readonly constructor?: unknown;
}

/**
 * The SDK's classes keep `name` as `Error`, so the class shows only in the
 * constructor's name.
 */
function blobErrorName(failure: BlobFailure): BlobErrorName | undefined {
  if (isBlobErrorName(failure.name)) {
    return failure.name;
  }

  const { constructor } = failure;

  const className: unknown =
    typeof constructor === "function" ? constructor.name : undefined;

  return isBlobErrorName(className) ? className : undefined;
}

/**
 * Maps a `@vercel/blob` error to a `DbError`; `not_found` keeps Storage's
 * `NoSuchKey`.
 */
function fromBlobError(cause: unknown): DbError {
  if (typeof cause !== "object" || cause === null) {
    return dbError("network", String(cause));
  }

  // SAFETY: cause is a non-null object, and every BlobFailure field is
  // optional and read as unknown.
  const failure = cause as BlobFailure;

  if (failure.name === "AbortError") {
    return toDbError(cause);
  }

  const message =
    typeof failure.message === "string" && failure.message !== ""
      ? failure.message
      : "Vercel Blob failed";

  const name = blobErrorName(failure);

  if (name === undefined) {
    return /already exists/iu.test(message)
      ? dbError("conflict", message)
      : dbError("network", message);
  }

  const kind = BLOB_ERRORS[name];

  switch (kind) {
    case "not_found": {
      return dbError("not_found", message, { code: "NoSuchKey" });
    }

    case "forbidden": {
      return dbError("forbidden", message, { code: name });
    }

    case "rate_limited": {
      const seconds = failure.retryAfter;

      return dbError("rate_limited", message, {
        code: name,
        ...(typeof seconds === "number" && seconds > 0
          ? { retryAfter: seconds }
          : {}),
      });
    }

    case "invalid_input": {
      return dbError("invalid_input", message, { code: name });
    }

    default: {
      const never: never = kind;

      return never;
    }
  }
}

function attempt<T>(run: () => PromiseLike<T>): AsyncResult<T> {
  return AsyncResult.from(async (): Promise<Result<T>> => {
    try {
      return ok(await run());
    } catch (cause) {
      return err(fromBlobError(cause));
    }
  });
}

const bodyOf = (body: FileBody): Blob | ArrayBuffer =>
  body instanceof Uint8Array ? new Uint8Array(body).buffer : body;

/** Supabase signed upload URLs last two hours. */
const UPLOAD_TTL = 7200;

/**
 * Vercel Blob as a `FileStore`. Blobs are private by default and read through
 * signed URLs; a pathname is `${prefix}${bucket}/${path}`. Blob has no image
 * transforms, public bucket URLs or upload claim, so the blocks refuse those,
 * and a `download` name is ignored: the browser saves the file under its
 * pathname.
 */
export function vercelBlobStore(
  blob: VercelBlobModule,
  options: VercelBlobStoreOptions = {},
): FileStore {
  const access = options.access ?? "private";
  const prefix = options.prefix ?? "";
  const auth = options.token === undefined ? {} : { token: options.token };

  const pathname = (bucket: string, path: string): string =>
    `${prefix}${bucket}/${path}`;

  return {
    apiVersion: 1,
    name: "vercel-blob",
    put: (bucket, path, body, put = {}) =>
      attempt(() =>
        blob.put(pathname(bucket, path), bodyOf(body), {
          access,
          ...(put.contentType === undefined
            ? {}
            : { contentType: put.contentType }),
          allowOverwrite: put.upsert ?? false,
          addRandomSuffix: false,
          ...auth,
        }),
      ).map(() => undefined),
    get: (bucket, path) =>
      attempt(() =>
        blob.get(pathname(bucket, path), { access, ...auth }),
      ).andThen(async (found): Promise<Result<Blob>> => {
        if (found === null) {
          return err(
            dbError("not_found", "Vercel Blob has no file at this path", {
              code: "NoSuchKey",
            }),
          );
        }

        if (found.stream === null) {
          return err(dbError("network", "Vercel Blob returned no body"));
        }

        const { stream } = found;
        const bytes = await attempt(() => new Response(stream).arrayBuffer());

        return bytes.ok
          ? ok(new Blob([bytes.data], { type: found.blob.contentType ?? "" }))
          : bytes;
      }),
    delete: (bucket, paths) =>
      paths.length === 0
        ? AsyncResult.ok(undefined)
        : attempt(() =>
            blob.del(
              paths.map((path) => pathname(bucket, path)),
              auth,
            ),
          ),
    signedUrl: (bucket, path, { expiresIn, download }) => {
      const target = pathname(bucket, path);
      const validUntil = Date.now() + expiresIn * 1000;

      return attempt(async () => {
        const token = await blob.issueSignedToken({
          pathname: target,
          operations: ["get"],
          validUntil,
          ...auth,
        });

        const { presignedUrl } = await blob.presignUrl(token, {
          operation: "get",
          pathname: target,
          validUntil,
          access,
        });

        return download === undefined ||
          download === false ||
          blob.getDownloadUrl === undefined
          ? presignedUrl
          : blob.getDownloadUrl(presignedUrl);
      });
    },
    head: (bucket, path) =>
      AsyncResult.from(async () => {
        const found = await attempt(() =>
          blob.head(pathname(bucket, path), auth),
        );

        if (!found.ok) {
          return found.error.kind === "not_found" ? ok(undefined) : found;
        }

        return ok({
          size: found.data.size,
          contentType: found.data.contentType,
        });
      }),
    signedUploadUrl: (bucket, path, upload) => {
      const target = pathname(bucket, path);
      const validUntil = Date.now() + (upload.expiresIn ?? UPLOAD_TTL) * 1000;

      const limits = {
        ...(upload.contentType === undefined
          ? {}
          : { allowedContentTypes: [upload.contentType] }),
        ...(upload.maxSize === undefined
          ? {}
          : { maximumSizeInBytes: upload.maxSize }),
      };

      return attempt(async (): Promise<SignedUpload> => {
        const token = await blob.issueSignedToken({
          pathname: target,
          operations: ["put"],
          validUntil,
          ...limits,
          ...auth,
        });

        const { presignedUrl } = await blob.presignUrl(token, {
          operation: "put",
          pathname: target,
          validUntil,
          access,
          allowOverwrite: false,
          addRandomSuffix: false,
          ...limits,
        });

        return {
          url: presignedUrl,
          method: "PUT",
          headers: {
            "x-vercel-blob-access": access,
            ...(upload.contentType === undefined
              ? {}
              : { "x-content-type": upload.contentType }),
          },
        };
      });
    },
  };
}
