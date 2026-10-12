import type { SqlClient } from "../postgres/executor.ts";

import { type DbError, dbError, mapDbError } from "../core/errors.ts";
import { isRecord } from "../core/guards.ts";
import { AsyncResult, err, ok, toDbError } from "../core/result.ts";
import { fromPgError } from "../postgres/executor.ts";
import { fromStorageError } from "../storage/errors.ts";

interface StorageResponse<T> {
  readonly data: T | null;
  readonly error: unknown;
}

/** The part of a service-role supabase-js `storage` client that `supportStorage` uses. */
export interface SupportStorageAdmin {
  from(bucket: string): {
    download(path: string): PromiseLike<StorageResponse<Blob>>;
    createSignedUrl(
      path: string,
      expiresIn: number,
      options?: { download?: string | boolean },
    ): PromiseLike<StorageResponse<{ readonly signedUrl: string }>>;
    list(
      path?: string,
      options?: SupportStorageListOptions,
    ): PromiseLike<StorageResponse<readonly unknown[]>>;
  };
}

export interface SupportStorageListOptions {
  readonly limit?: number;
  readonly offset?: number;
  readonly search?: string;
}

/** One entry of a folder listing: a file, or a folder when `id` is `null`. */
export interface SupportStorageEntry {
  readonly name: string;
  readonly id: string | null;
  readonly createdAt?: string;
  readonly updatedAt?: string;
  readonly metadata?: Readonly<Record<string, unknown>>;
}

/** One bucket, read as the support session's target. */
export interface SupportStorageBucket {
  /** The object, when the target may read it; `not_found` otherwise. */
  download(path: string): AsyncResult<Blob>;
  /** A signed URL for the object, when the target may read it. */
  createSignedUrl(
    path: string,
    expiresIn: number,
    options?: { readonly download?: string | boolean },
  ): AsyncResult<string>;
  /** The files and folders under `prefix` that the target may read. */
  list(
    prefix?: string,
    options?: SupportStorageListOptions,
  ): AsyncResult<readonly SupportStorageEntry[]>;
  /**
   * Always fails: `forbidden` (`SUPPORT_READ_ONLY`) in a read-only session,
   * `unsupported` (`SUPPORT_STORAGE_WRITES`) in a writable one.
   */
  upload(path: string, body: unknown): AsyncResult<never>;
}

/** Storage as the target of a support session: `ctx.storage`. */
export interface SupportStorage {
  from(bucket: string): SupportStorageBucket;
}

export interface SupportStorageOptions {
  /** The service-role storage client that performs each operation. */
  readonly admin: SupportStorageAdmin;
  /** Runs as the target, such as `postgres.asUser(support.claims)`, so RLS on `storage.objects` decides. */
  readonly sql: SqlClient;
  /** Whether the session is read-only. Defaults to true. */
  readonly readOnly?: boolean;
}

const VISIBLE_OBJECT =
  "select exists (select 1 from storage.objects o where o.bucket_id = $1 and o.name = $2) as visible";

const VISIBLE_ENTRIES = `select n.path from unnest($2::text[]) as n(path)
where exists (
  select 1 from storage.objects o
  where o.bucket_id = $1
    and (o.name = n.path or left(o.name, length(n.path) + 1) = n.path || '/')
)`;

function sqlError(cause: unknown): DbError {
  const raw = fromPgError(cause);
  return raw ? mapDbError(raw) : toDbError(cause);
}

const notFound = (bucket: string, path: string): DbError =>
  dbError("not_found", `No object ${path} in bucket ${bucket}`, {
    code: "SUPPORT_STORAGE_NOT_FOUND",
  });

const optionalText = (value: unknown): string | undefined =>
  typeof value === "string" ? value : undefined;

function entryOf(value: unknown): SupportStorageEntry | undefined {
  if (!isRecord(value) || typeof value["name"] !== "string") return;
  const createdAt = optionalText(value["created_at"]);
  const updatedAt = optionalText(value["updated_at"]);
  const metadata = value["metadata"];
  return {
    name: value["name"],
    id: optionalText(value["id"]) ?? null,
    ...(createdAt === undefined ? {} : { createdAt }),
    ...(updatedAt === undefined ? {} : { updatedAt }),
    ...(isRecord(metadata) ? { metadata } : {}),
  };
}

/**
 * Storage for a support session. Storage policies read `auth.uid()` from the
 * request's token, and there is no token for the target, so each call first
 * checks over Postgres, as the target, that RLS lets them see the object
 * (or, for `list`, which entries), and only then reads it with the service
 * client. Writes are refused.
 */
export function supportStorage(options: SupportStorageOptions): SupportStorage {
  const readOnly = options.readOnly ?? true;
  const visible = async (bucket: string, path: string): Promise<boolean> => {
    const [row] = await options.sql.queryRaw<{ visible: boolean }>(
      VISIBLE_OBJECT,
      [bucket, path],
    );
    return row?.visible === true;
  };
  /** Runs `read` with the service client once the target may see the object. */
  const checked = <T>(
    bucket: string,
    path: string,
    read: () => PromiseLike<StorageResponse<T>>,
  ): AsyncResult<T> =>
    AsyncResult.from(async () => {
      try {
        if (!(await visible(bucket, path))) return err(notFound(bucket, path));
      } catch (cause) {
        return err(sqlError(cause));
      }
      try {
        const { data, error } = await read();
        if (error) return err(fromStorageError(error, bucket));
        return data === null ? err(notFound(bucket, path)) : ok(data);
      } catch (cause) {
        return err(fromStorageError(cause, bucket));
      }
    });
  return {
    from(bucket) {
      const api = () => options.admin.from(bucket);
      return {
        download: (path) => checked(bucket, path, () => api().download(path)),
        createSignedUrl: (path, expiresIn, urlOptions) =>
          checked(bucket, path, () =>
            api().createSignedUrl(
              path,
              expiresIn,
              urlOptions?.download === undefined
                ? undefined
                : { download: urlOptions.download },
            ),
          ).map((data) => data.signedUrl),
        list: (prefix = "", listOptions) =>
          AsyncResult.from(async () => {
            let entries: SupportStorageEntry[];
            try {
              const { data, error } = await api().list(prefix, listOptions);
              if (error) return err(fromStorageError(error, bucket));
              entries = (data ?? []).flatMap((value) => entryOf(value) ?? []);
            } catch (cause) {
              return err(fromStorageError(cause, bucket));
            }
            if (entries.length === 0) return ok(entries);
            const folder = prefix.replace(/\/+$/, "");
            const pathOf = (entry: SupportStorageEntry) =>
              folder === "" ? entry.name : `${folder}/${entry.name}`;
            let seen: Set<string>;
            try {
              const rows = await options.sql.queryRaw<{ path: string }>(
                VISIBLE_ENTRIES,
                [bucket, entries.map(pathOf)],
              );
              seen = new Set(rows.map((row) => row.path));
            } catch (cause) {
              return err(sqlError(cause));
            }
            return ok(entries.filter((entry) => seen.has(pathOf(entry))));
          }),
        upload: () =>
          AsyncResult.err(
            readOnly
              ? dbError("forbidden", "The support session is read-only", {
                  code: "SUPPORT_READ_ONLY",
                })
              : dbError(
                  "unsupported",
                  "Uploads are not available in a support session",
                  { code: "SUPPORT_STORAGE_WRITES" },
                ),
          ),
      };
    },
  };
}
