import type {
  FileBody,
  SupabaseFileStorage,
  VercelBlobModule,
} from "../../src/storage/file-store.ts";

export interface Stored {
  readonly bytes: Uint8Array;
  readonly contentType: string;
}

async function bytesOf(body: FileBody | Blob): Promise<Uint8Array> {
  if (body instanceof Blob) {
    return new Uint8Array(await body.arrayBuffer());
  }

  return new Uint8Array(body);
}

export class BlobError extends Error {
  constructor(message: string) {
    super(`Vercel Blob: ${message}`);
  }
}

/**
 * Like the SDK's classes: `name` stays `Error`, the class name tells them
 * apart.
 */
export class BlobNotFoundError extends BlobError {
  constructor() {
    super("The requested blob does not exist");
  }
}

export class BlobAccessError extends BlobError {
  constructor() {
    super("Access denied, please provide a valid token for this resource.");
  }
}

export class BlobServiceRateLimited extends BlobError {
  readonly retryAfter: number;

  constructor(seconds: number) {
    super("Too many requests please lower the number of concurrent requests");
    this.retryAfter = seconds;
  }
}

export class BlobFileTooLargeError extends BlobError {
  constructor() {
    super("File is too large");
  }
}

export class BlobContentTypeNotAllowedError extends BlobError {
  constructor() {
    super("Content type mismatch");
  }
}

const STORE = "https://store.private.blob.vercel-storage.com";

/**
 * An in-memory `@vercel/blob` module. Presigned URLs carry the pathname and
 * operation in the query, and `fetch` serves and accepts them.
 */
export interface FakeBlobModule {
  readonly module: VercelBlobModule;
  readonly blobs: Map<string, Stored>;
  readonly calls: [string, ...unknown[]][];
  readonly fetch: (url: string, init?: RequestInit) => Promise<Response>;
}

export function fakeBlobModule(
  options: {
    readonly fail?: Partial<Record<string, Error>>;
    /** Leaves out `getDownloadUrl`, as an older SDK might. */
    readonly downloadUrl?: false;
  } = {},
): FakeBlobModule {
  const blobs = new Map<string, Stored>();
  const calls: [string, ...unknown[]][] = [];

  const failing = (method: string): void => {
    const failure = options.fail?.[method];

    if (failure !== undefined) {
      throw failure;
    }
  };

  const module = {
    async put(pathname, body, put) {
      calls.push(["put", pathname, put]);
      failing("put");

      if (blobs.has(pathname) && put.allowOverwrite !== true) {
        throw new BlobError(
          "This blob already exists, use `allowOverwrite: true` if you want to overwrite it.",
        );
      }

      blobs.set(pathname, {
        bytes: await bytesOf(body),
        contentType: put.contentType ?? "application/octet-stream",
      });

      return { pathname, url: `${STORE}/${pathname}` };
    },
    async get(pathname, get) {
      calls.push(["get", pathname, get]);
      failing("get");
      const found = blobs.get(pathname);

      if (found === undefined) {
        return null;
      }

      return {
        statusCode: 200,
        stream: new Blob([new Uint8Array(found.bytes)]).stream(),
        blob: { contentType: found.contentType, size: found.bytes.length },
      };
    },
    async head(pathname, head) {
      calls.push(["head", pathname, head]);
      failing("head");
      const found = blobs.get(pathname);

      if (found === undefined) {
        throw new BlobNotFoundError();
      }

      return { size: found.bytes.length, contentType: found.contentType };
    },
    async del(pathnames, del) {
      calls.push(["del", pathnames, del]);
      failing("del");

      for (const pathname of pathnames) {
        blobs.delete(pathname);
      }
    },
    async issueSignedToken(issue) {
      calls.push(["issueSignedToken", issue]);
      failing("issueSignedToken");

      return {
        clientSigningToken: "signing",
        delegationToken: `delegation:${issue.pathname ?? "*"}`,
        validUntil: issue.validUntil ?? 0,
      };
    },
    async presignUrl(token, presign) {
      calls.push(["presignUrl", token, presign]);
      failing("presignUrl");
      const url = new URL(`${STORE}/${presign.pathname}`);
      url.searchParams.set("vercel-blob-operation", presign.operation);

      return { presignedUrl: url.toString() };
    },
  } satisfies VercelBlobModule;

  const getDownloadUrl = (blobUrl: string): string => {
    const url = new URL(blobUrl);
    url.searchParams.set("download", "1");

    return url.toString();
  };

  const fetch = async (
    url: string,
    init: RequestInit = {},
  ): Promise<Response> => {
    const parsed = new URL(url);
    const pathname = decodeURIComponent(parsed.pathname.slice(1));
    const operation = parsed.searchParams.get("vercel-blob-operation");

    if (operation === "put" && init.body instanceof Blob) {
      const headers = new Headers(init.headers);

      blobs.set(pathname, {
        bytes: await bytesOf(init.body),
        contentType:
          headers.get("x-content-type") ??
          headers.get("content-type") ??
          "application/octet-stream",
      });

      return new Response(null, { status: 200 });
    }

    const found = blobs.get(pathname);

    return operation === "get" && found !== undefined
      ? new Response(new Uint8Array(found.bytes), { status: 200 })
      : new Response(null, { status: 404 });
  };

  return {
    module:
      options.downloadUrl === false ? module : { ...module, getDownloadUrl },
    blobs,
    calls,
    fetch,
  };
}

/** A Storage error like `StorageApiError`. */
const storageError = (message: string, statusCode: string) => ({
  name: "StorageApiError",
  message,
  statusCode,
});

/**
 * An in-memory `supabase.storage` with the methods `supabaseFileStore` calls.
 * Signed URLs carry the object key, and `fetch` serves and accepts them.
 */
export interface FakeSupabaseStorage {
  readonly storage: SupabaseFileStorage;
  readonly objects: Map<string, Stored>;
  readonly calls: [string, ...unknown[]][];
  readonly fetch: (url: string, init?: RequestInit) => Promise<Response>;
}

export function fakeSupabaseStorage(): FakeSupabaseStorage {
  const objects = new Map<string, Stored>();
  const calls: [string, ...unknown[]][] = [];

  const storage = {
    from: (bucket: string) => {
      const key = (path: string): string => `${bucket}/${path}`;

      return {
        async upload(
          path: string,
          body: FileBody,
          upload?: { readonly contentType?: string; readonly upsert?: boolean },
        ) {
          calls.push(["upload", bucket, path, upload]);

          if (objects.has(key(path)) && upload?.upsert !== true) {
            return {
              data: null,
              error: storageError("The resource already exists", "409"),
            };
          }

          objects.set(key(path), {
            bytes: await bytesOf(body),
            contentType: upload?.contentType ?? "application/octet-stream",
          });

          return { data: { path }, error: null };
        },
        async download(path: string) {
          calls.push(["download", bucket, path]);
          const found = objects.get(key(path));

          return found === undefined
            ? { data: null, error: storageError("Object not found", "404") }
            : {
                data: new Blob([new Uint8Array(found.bytes)], {
                  type: found.contentType,
                }),
                error: null,
              };
        },
        async remove(paths: string[]) {
          calls.push(["remove", bucket, paths]);

          for (const path of paths) {
            objects.delete(key(path));
          }

          return { data: [], error: null };
        },
        async createSignedUrl(
          path: string,
          expiresIn: number,
          signed?: unknown,
        ) {
          calls.push(["createSignedUrl", bucket, path, expiresIn, signed]);

          return {
            data: {
              signedUrl: `https://storage.test/sign/${key(path)}?ttl=${String(expiresIn)}`,
            },
            error: null,
          };
        },
        async createSignedUploadUrl(path: string) {
          calls.push(["createSignedUploadUrl", bucket, path]);

          return {
            data: {
              signedUrl: `https://storage.test/upload/sign/${key(path)}?token=t`,
              token: "t",
            },
            error: null,
          };
        },
        async info(path: string) {
          calls.push(["info", bucket, path]);
          const found = objects.get(key(path));

          return found === undefined
            ? { data: null, error: storageError("Object not found", "404") }
            : {
                data: {
                  size: found.bytes.length,
                  contentType: found.contentType,
                },
                error: null,
              };
        },
      };
    },
  } satisfies SupabaseFileStorage;

  const fetch = async (
    url: string,
    init: RequestInit = {},
  ): Promise<Response> => {
    const parsed = new URL(url);
    const [, kind, ...rest] = parsed.pathname.split("/");
    const objectKey = (kind === "upload" ? rest.slice(1) : rest).join("/");

    if (kind === "upload" && init.body instanceof Blob) {
      objects.set(objectKey, {
        bytes: await bytesOf(init.body),
        contentType:
          new Headers(init.headers).get("content-type") ??
          "application/octet-stream",
      });

      return new Response(null, { status: 200 });
    }

    const found = objects.get(objectKey);

    return found === undefined
      ? new Response(null, { status: 404 })
      : new Response(new Uint8Array(found.bytes), { status: 200 });
  };

  return { storage, objects, calls, fetch };
}
