import type { StorageClient } from "../../src/storage/index.ts";

export interface StoredFile {
  readonly body: unknown;
  readonly contentType: string | undefined;
  readonly size: number | undefined;
  readonly createdAt: string;
}

type Method =
  | "upload"
  | "download"
  | "exists"
  | "remove"
  | "list"
  | "createSignedUrl"
  | "createSignedUrls"
  | "createSignedUploadUrl"
  | "uploadToSignedUrl";

export interface StorageCall {
  readonly bucket: string;
  readonly method: Method;
  readonly args: readonly unknown[];
}

/** A Storage error like `StorageApiError`. */
export function storageError(
  message: string,
  fields: {
    status?: number;
    statusCode?: string;
    code?: string;
    name?: string;
  } = {},
): Record<string, unknown> {
  return { name: "StorageApiError", message, ...fields };
}

function sizeOf(body: unknown): number | undefined {
  if (typeof body === "string") return new TextEncoder().encode(body).length;
  if (body instanceof Blob) return body.size;
  if (body instanceof ArrayBuffer) return body.byteLength;
  if (ArrayBuffer.isView(body)) return body.byteLength;
  return undefined;
}

/**
 * An in-memory Storage API with the `storage.from(bucket)` methods buckets
 * use. `fail` makes a method answer with an error (or throw) instead.
 */
export function fakeStorage(
  options: {
    readonly files?: Readonly<Record<string, string>>;
    readonly now?: string;
    readonly fail?: Partial<Record<Method, unknown>>;
    readonly throws?: Partial<Record<Method, unknown>>;
  } = {},
): {
  client: StorageClient;
  files: Map<string, StoredFile>;
  calls: StorageCall[];
} {
  const files = new Map<string, StoredFile>();
  const createdAt = options.now ?? "2026-01-01T00:00:00.000Z";
  for (const [key, body] of Object.entries(options.files ?? {}))
    files.set(key, {
      body,
      contentType: undefined,
      size: body.length,
      createdAt,
    });
  const calls: StorageCall[] = [];

  const from = (bucket: string) => {
    const key = (path: string) => `${bucket}/${path}`;
    const record = (method: Method, args: unknown[]) => {
      calls.push({ bucket, method, args });
      // oxlint-disable-next-line typescript/only-throw-error -- storage-js can reject with plain objects, and the tests replay those.
      if (options.throws?.[method] !== undefined) throw options.throws[method];
      const error = options.fail?.[method];
      return error === undefined ? undefined : { data: null, error };
    };
    const put = (
      path: string,
      body: unknown,
      opts?: { contentType?: string },
    ) =>
      files.set(key(path), {
        body,
        contentType: opts?.contentType,
        size: sizeOf(body),
        createdAt,
      });
    return {
      async upload(
        path: string,
        body: unknown,
        opts?: { contentType?: string; upsert?: boolean },
      ) {
        const failed = record("upload", [path, body, opts]);
        if (failed) return failed;
        if (files.has(key(path)) && !opts?.upsert)
          return {
            data: null,
            error: storageError("The resource already exists", {
              statusCode: "409",
            }),
          };
        put(path, body, opts);
        return { data: { path, id: path, fullPath: key(path) }, error: null };
      },
      async download(path: string, ...rest: unknown[]) {
        const failed = record("download", [path, ...rest]);
        if (failed) return failed;
        const file = files.get(key(path));
        if (!file)
          return {
            data: null,
            error: storageError("Object not found", { statusCode: "404" }),
          };
        return { data: new Blob([String(file.body)]), error: null };
      },
      async exists(path: string) {
        const failed = record("exists", [path]);
        if (failed) return { data: true, error: failed.error };
        return { data: files.has(key(path)), error: null };
      },
      async remove(paths: string[]) {
        const failed = record("remove", [paths]);
        if (failed) return failed;
        for (const path of paths) files.delete(key(path));
        return { data: paths.map((name) => ({ name })), error: null };
      },
      async list(folder: string, opts?: { limit?: number; offset?: number }) {
        const failed = record("list", [folder, opts]);
        if (failed) return failed;
        const prefix = folder ? `${bucket}/${folder}/` : `${bucket}/`;
        const entries = new Map<string, Record<string, unknown>>();
        for (const [name, file] of files) {
          if (!name.startsWith(prefix)) continue;
          const rest = name.slice(prefix.length);
          const [head, ...tail] = rest.split("/");
          if (tail.length > 0)
            entries.set(head!, { name: head, id: null, metadata: null });
          else
            entries.set(head!, {
              name: head,
              id: name,
              metadata: { size: file.size, mimetype: file.contentType },
              created_at: file.createdAt,
              updated_at: file.createdAt,
            });
        }
        const sorted = [...entries.values()].toSorted((a, b) =>
          String(a["name"]).localeCompare(String(b["name"])),
        );
        const offset = opts?.offset ?? 0;
        return {
          data: sorted.slice(offset, offset + (opts?.limit ?? 100)),
          error: null,
        };
      },
      async createSignedUrl(path: string, ttl: number, opts?: unknown) {
        const failed = record("createSignedUrl", [path, ttl, opts]);
        if (failed) return failed;
        return {
          data: {
            signedUrl: `https://storage.test/sign/${key(path)}?ttl=${ttl}`,
          },
          error: null,
        };
      },
      async createSignedUrls(paths: string[], ttl: number, opts?: unknown) {
        const failed = record("createSignedUrls", [paths, ttl, opts]);
        if (failed) return failed;
        return {
          data: paths.map((path) =>
            files.has(key(path))
              ? {
                  path,
                  error: null,
                  signedUrl: `https://storage.test/sign/${key(path)}?ttl=${ttl}`,
                }
              : {
                  path,
                  error:
                    "Either the object does not exist or you do not have access to it",
                  signedUrl: "",
                },
          ),
          error: null,
        };
      },
      getPublicUrl(
        path: string,
        opts?: { download?: unknown; transform?: unknown },
      ) {
        const mode = opts?.transform ? "render/image/public" : "object/public";
        return {
          data: { publicUrl: `https://storage.test/${mode}/${key(path)}` },
        };
      },
      async createSignedUploadUrl(path: string, opts?: unknown) {
        const failed = record("createSignedUploadUrl", [path, opts]);
        if (failed) return failed;
        return {
          data: {
            path,
            token: `token-${path}`,
            signedUrl: `https://storage.test/upload/${key(path)}`,
          },
          error: null,
        };
      },
      async uploadToSignedUrl(
        path: string,
        token: string,
        body: unknown,
        opts?: { contentType?: string },
      ) {
        const failed = record("uploadToSignedUrl", [path, token, body, opts]);
        if (failed) return failed;
        put(path, body, opts);
        return { data: { path, fullPath: key(path) }, error: null };
      },
    };
  };
  // SAFETY: the fake implements the `storage.from()` methods buckets call.
  const client = { storage: { from } } as unknown as StorageClient;
  return { client, files, calls };
}
