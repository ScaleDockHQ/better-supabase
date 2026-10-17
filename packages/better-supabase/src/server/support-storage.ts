import type { SupportSession } from "../auth/support.ts";
import type { SqlClient } from "../postgres/executor.ts";
import type {
  StorageApi,
  StorageBucketApi,
  StorageDestinationOptions,
  StorageFailure,
  StorageFileOptions,
  StorageListEntry,
  StorageListV2Folder,
  StorageListV2Object,
  StorageListV2Result,
  StorageObjectInfo,
  StorageRemoveEntry,
  StorageResponse,
  StorageSearchOptions,
  StorageSearchV2Options,
  StorageSignedUrlEntry,
} from "../storage/storage-api.ts";

import { type DbError, mapDbError } from "../core/errors.ts";
import { isRecord } from "../core/guards.ts";
import { toDbError } from "../core/result.ts";
import { fromPgError } from "../postgres/executor.ts";

export interface SupportStorageOptions {
  /** The service-role `supabase.storage` that serves what the target may read. */
  readonly admin: StorageApi;
  /** Runs as the target, such as `postgres.asUser(support.claims)`, so RLS on `storage.objects` decides. Writes need its `transaction`. */
  readonly sql: SqlClient;
  /** Runs as the connection-string role, such as `postgres.admin`. Writes need it to make the target the owner of what they store. */
  readonly adminSql?: SqlClient;
  /** The session the writes are recorded under. Writes need it. */
  readonly session?: Pick<SupportSession, "id" | "adminId" | "targetUserId">;
  /** Whether the session is read-only. Defaults to true. */
  readonly readOnly?: boolean;
}

type Row = Readonly<Record<string, unknown>>;

const VISIBLE_OBJECT =
  "select exists (select 1 from storage.objects o where o.bucket_id = $1 and o.name = $2) as visible";

const VISIBLE_OBJECTS = `select n.path from unnest($2::text[]) as n(path)
where exists (select 1 from storage.objects o where o.bucket_id = $1 and o.name = n.path)`;

const OBJECT_INFO =
  "select to_jsonb(o) as object from storage.objects o where o.bucket_id = $1 and o.name = $2";

const SEARCH = `select s.name, s.id::text as id, s.updated_at, s.created_at, s.last_accessed_at, s.metadata
from storage.search($1::text, $2::text, $3::int, $4::int, $5::int, $6::text, $7::text, $8::text) s`;

const SEARCH_V2 = `select s.key, s.name, s.id::text as id, s.updated_at, s.created_at, s.last_accessed_at, s.metadata
from storage.search_v2($1::text, $2::text, $3::int, $4::int, $5::text, $6::text, $7::text, $8::text) s`;

const SAVEPOINT = "better_supabase_support_write";

const INSERT_OBJECT = `insert into storage.objects (bucket_id, name, owner, owner_id, user_metadata)
values ($1, $2, $3::uuid, $4, $5::jsonb)`;

const CURRENT_VERSION_INDEX = `select exists (select 1 from pg_indexes
where schemaname = 'storage' and tablename = 'objects' and indexname = 'idx_objects_current_version') as versioned`;

const upsertObject = (versioned: boolean): string => `${INSERT_OBJECT}
on conflict ${versioned ? '(bucket_id, name collate "C") where archived_at is null' : "(bucket_id, name)"} do update
set owner = excluded.owner, owner_id = excluded.owner_id, user_metadata = excluded.user_metadata`;

const SOURCE_OBJECT =
  "select name, owner_id from storage.objects where bucket_id = $1 and name = $2";

const MOVE_OBJECT = `update storage.objects
set bucket_id = $3, name = $4, owner = $5::uuid, owner_id = $6
where bucket_id = $1 and name = $2
returning name`;

// Storage refuses a direct delete on `storage.objects` without this flag.
// It is set locally inside the rehearsal's savepoint, which is always rolled
// back, so the delete only reports which rows the target's policies allow.
const ALLOW_DELETE =
  "select set_config('storage.allow_delete_query', 'true', true)";

const DELETE_OBJECTS =
  "delete from storage.objects where bucket_id = $1 and name = any($2::text[]) returning name";

const OWN_UPLOAD = `update storage.objects set owner = $3::uuid, owner_id = $4
where bucket_id = $1 and name = $2 and user_metadata ->> 'supportSessionId' = $5`;

const OWN_COPY = `update storage.objects
set owner = $3::uuid, owner_id = $4, user_metadata = coalesce(user_metadata, '{}'::jsonb) || $5::jsonb
where bucket_id = $1 and name = $2 and owner_id is null`;

const OWN_MOVE = `update storage.objects
set owner = $3::uuid, owner_id = $4, user_metadata = coalesce(user_metadata, '{}'::jsonb) || $5::jsonb
where bucket_id = $1 and name = $2 and owner_id is not distinct from $6`;

const UUID = /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i;

const HIDDEN_URL =
  "Either the object does not exist or you do not have access to it";

const LIST_SORT_COLUMNS = new Set([
  "name",
  "updated_at",
  "created_at",
  "last_accessed_at",
]);

const LIST_V2_SORT_COLUMNS = new Set(["name", "updated_at", "created_at"]);
const FLAT_SORT_COLUMNS = new Set(["updated_at", "created_at"]);
const SORT_ORDERS = new Set(["asc", "desc"]);

const CURSOR_PARTS = {
  l: "startAfter",
  o: "sortOrder",
  c: "sortColumn",
  a: "sortColumnAfter",
} as const;

type CursorPart = (typeof CURSOR_PARTS)[keyof typeof CURSOR_PARTS];

type Cursor = Partial<Record<CursorPart, string>>;

const isCursorKey = (key: string): key is keyof typeof CURSOR_PARTS =>
  Object.hasOwn(CURSOR_PARTS, key);

/** The path storage-js sends for an upload: no leading or trailing `/`, and no empty folders. */
function normalizePath(path: string): string {
  return path.replaceAll(/^\/|\/$/g, "").replaceAll(/\/+/g, "/");
}

/** `undefined` for an empty string, which storage-api treats as absent. */
const filled = (value: string | undefined): string | undefined =>
  value === "" ? undefined : value;

/** `LIKE` escaping as storage-api applies it. */
function escapeLike(text: string): string {
  return text.replaceAll("\\", "\\\\").replaceAll(/([%_])/g, "\\$1");
}

function iso(value: unknown): unknown {
  if (value instanceof Date) {
    return value.toISOString();
  }

  if (typeof value !== "string") {
    return value;
  }

  const time = Date.parse(value);

  return Number.isNaN(time) ? value : new Date(time).toISOString();
}

/** storage-api's continuation token: `key:value` lines, base64 encoded. */
function encodeCursor(cursor: Cursor): string {
  const text = Object.entries(CURSOR_PARTS)
    .flatMap(([key, part]) => (cursor[part] ? [`${key}:${cursor[part]}`] : []))
    .join("\n");

  let binary = "";

  for (const byte of new TextEncoder().encode(text)) {
    binary += String.fromCodePoint(byte);
  }

  return btoa(binary);
}

function decodeCursor(token: string): Cursor | undefined {
  let text: string;

  try {
    text = new TextDecoder().decode(
      Uint8Array.from(atob(token), (char) => char.codePointAt(0) ?? 0),
    );
  } catch {
    return undefined;
  }

  const cursor: Cursor = { startAfter: "", sortOrder: "asc" };

  for (const part of text.split("\n")) {
    const match = /^(\S):(.*)/.exec(part);
    const key = match?.[1];

    if (!key || !isCursorKey(key)) {
      return undefined;
    }

    cursor[CURSOR_PARTS[key]] = match[2] ?? "";
  }

  return cursor;
}

const apiError = (
  status: number,
  message: string,
  code: string,
): StorageFailure => ({
  name: "StorageApiError",
  message,
  status,
  statusCode: String(status),
  code,
});

const ownerOf = (userId: string): string | null =>
  UUID.test(userId) ? userId : null;

const stampOf = (
  session: Pick<SupportSession, "id" | "adminId">,
): Readonly<Record<string, string>> => ({
  supportSessionId: session.id,
  supportAdminId: session.adminId,
});

const failed = <T>(error: StorageFailure): StorageResponse<T> => ({
  data: null,
  error,
});

/** Storage answers a hidden object like a missing one: HTTP 400 with `statusCode` 404. */
const NOT_FOUND: StorageFailure = {
  name: "StorageApiError",
  message: "Object not found",
  status: 400,
  statusCode: "404",
  code: "NoSuchKey",
};

const invalid = (message: string): StorageFailure =>
  apiError(400, message, "InvalidRequest");

/** A database failure as a Storage `error` that `fromStorageError` passes through unchanged. */
function sqlFailure(cause: unknown): StorageFailure {
  const raw = fromPgError(cause);
  const error: DbError = raw ? mapDbError(raw) : toDbError(cause);

  return { name: "DbError", ...error };
}

/** An RLS or duplicate failure of a dry run, as Storage reports it for the target's own request. */
function refusedWrite(cause: unknown): StorageFailure | undefined {
  const raw = fromPgError(cause);

  if (raw?.code === "42501") {
    return apiError(
      403,
      raw.message === undefined || raw.message.includes("row-level security")
        ? "new row violates row-level security policy"
        : raw.message,
      "AccessDenied",
    );
  }

  if (raw?.code === "23505") {
    return apiError(409, "The resource already exists", "Duplicate");
  }

  return undefined;
}

async function settled<T>(
  run: () => Promise<StorageResponse<T>>,
): Promise<StorageResponse<T>> {
  try {
    return await run();
  } catch (cause) {
    return failed(sqlFailure(cause));
  }
}

function listProblem(options: StorageSearchOptions): string | undefined {
  const { limit, offset, sortBy } = options;

  if (limit !== undefined && (!Number.isInteger(limit) || limit < 1)) {
    return "body/limit must be an integer of at least 1";
  }

  if (offset !== undefined && (!Number.isInteger(offset) || offset < 0)) {
    return "body/offset must be an integer of at least 0";
  }

  if (sortBy?.column !== undefined && !LIST_SORT_COLUMNS.has(sortBy.column)) {
    return "body/sortBy/column must be name, updated_at, created_at or last_accessed_at";
  }

  if (sortBy?.order !== undefined && !SORT_ORDERS.has(sortBy.order)) {
    return "body/sortBy/order must be asc or desc";
  }

  return undefined;
}

function listV2Problem(options: StorageSearchV2Options): string | undefined {
  const { limit, sortBy } = options;

  if (limit !== undefined && (!Number.isInteger(limit) || limit < 1)) {
    return "body/limit must be an integer of at least 1";
  }

  if (sortBy !== undefined && !LIST_V2_SORT_COLUMNS.has(sortBy.column)) {
    return "body/sortBy/column must be name, updated_at or created_at";
  }

  if (sortBy?.order !== undefined && !SORT_ORDERS.has(sortBy.order)) {
    return "body/sortBy/order must be asc or desc";
  }

  return undefined;
}

/** The query storage-api runs for a `list-v2` page without a delimiter. */
function flatPage(
  bucket: string,
  prefix: string | undefined,
  maxKeys: number,
  cursor: Cursor | undefined,
  column: string | undefined,
  order: string | undefined,
): { readonly text: string; readonly values: unknown[] } {
  const values: unknown[] = [bucket, maxKeys];
  const conditions = ["bucket_id = $1"];

  const sortColumn =
    column && FLAT_SORT_COLUMNS.has(column) ? column : undefined;

  const sortOrder = order && SORT_ORDERS.has(order) ? order : "asc";
  const operator = sortOrder === "asc" ? ">" : "<";
  const param = () => `$${String(values.length)}`;

  if (prefix) {
    values.push(`${escapeLike(prefix)}%`);
    conditions.push(`name like ${param()}`);
  }

  const startAfter = cursor?.startAfter;

  if (startAfter && sortColumn && cursor.sortColumnAfter) {
    values.push(cursor.sortColumnAfter);
    const afterParam = param();
    values.push(startAfter);
    conditions.push(
      `row(date_trunc('milliseconds', ${sortColumn}), name collate "C") ${operator} row(coalesce(nullif(${afterParam}, '')::timestamptz, 'epoch'::timestamptz), ${param()})`,
    );
  } else if (startAfter) {
    values.push(startAfter);
    conditions.push(`name collate "C" ${operator} ${param()}`);
  }

  return {
    text: `select id::text as id, name, metadata, updated_at, created_at, last_accessed_at
from storage.objects
where ${conditions.join(" and ")}
order by ${sortColumn ? `${sortColumn} ${sortOrder}, ` : ""}name collate "C" ${sortOrder}
limit $2::int`,
    values,
  };
}

/** Groups the entries below the next delimiter into folders, as storage-api does. */
function delimited(entries: readonly Row[], prefix: string): Row[] {
  const grouped: Row[] = [];
  let previous = "";

  for (const entry of entries) {
    const name = String(entry["name"]);
    const index = name.replace(prefix, "").indexOf("/");

    if (index === -1) {
      grouped.push(entry);
      continue;
    }

    const folder = name.slice(0, prefix.length + index + 1);

    if (folder === previous) {
      continue;
    }

    previous = folder;
    grouped.push({ id: null, name: folder });
  }

  return grouped;
}

const text = (value: unknown): string | undefined =>
  typeof value === "string" ? value : undefined;

const metadataOf = (
  value: unknown,
): Readonly<Record<string, unknown>> | null => (isRecord(value) ? value : null);

function listEntryOf(row: Row): StorageListEntry {
  return {
    name: String(row["name"]),
    id: text(row["id"]) ?? null,
    updated_at: text(iso(row["updated_at"])) ?? null,
    created_at: text(iso(row["created_at"])) ?? null,
    last_accessed_at: text(iso(row["last_accessed_at"])) ?? null,
    metadata: metadataOf(row["metadata"]),
  };
}

function folderOf(row: Row): StorageListV2Folder {
  const name = String(row["name"]);
  const key = text(row["key"]);

  return {
    name: name.endsWith("/") ? name : `${name}/`,
    ...(key === undefined ? {} : { key }),
  };
}

function objectOf(row: Row): StorageListV2Object {
  const key = text(row["key"]);
  const lastAccessed = text(iso(row["last_accessed_at"]));

  return {
    name: String(row["name"]),
    ...(key === undefined ? {} : { key }),
    id: text(row["id"]) ?? "",
    updated_at: text(iso(row["updated_at"])) ?? "",
    created_at: text(iso(row["created_at"])) ?? "",
    ...(lastAccessed === undefined ? {} : { last_accessed_at: lastAccessed }),
    metadata: metadataOf(row["metadata"]),
  };
}

function infoOf(row: Row): StorageObjectInfo {
  const metadata = isRecord(row["metadata"]) ? row["metadata"] : {};
  const size = metadata["size"];
  const contentType = text(metadata["mimetype"]);
  const cacheControl = text(metadata["cacheControl"]);
  const etag = text(metadata["eTag"]);
  const lastModified = text(iso(row["updated_at"]));
  const userMetadata = row["user_metadata"];
  const archivedAt = row["archived_at"];
  const deleteMarker = row["is_delete_marker"];
  const versioned = row["is_versioned"];

  return {
    id: text(row["id"]) ?? "",
    name: text(row["name"]) ?? "",
    version: text(row["version"]) ?? "",
    bucketId: text(row["bucket_id"]) ?? "",
    createdAt: text(iso(row["created_at"])) ?? "",
    ...(typeof size === "number" ? { size } : {}),
    ...(contentType === undefined ? {} : { contentType }),
    ...(cacheControl === undefined ? {} : { cacheControl }),
    ...(etag === undefined ? {} : { etag }),
    ...(lastModified === undefined ? {} : { lastModified }),
    ...(isRecord(userMetadata) ? { metadata: userMetadata } : {}),
    ...(archivedAt === undefined
      ? {}
      : { archivedAt: text(iso(archivedAt)) ?? null }),
    ...(typeof deleteMarker === "boolean"
      ? { isDeleteMarker: deleteMarker }
      : {}),
    ...(typeof versioned === "boolean" ? { isVersioned: versioned } : {}),
  };
}

/**
 * Storage for a support session, with the same `from(bucket)` file API as
 * `supabase.storage`, so `bucket.connect()` and the blocks take it.
 *
 * Storage policies read `auth.uid()` from the request's token, and there is
 * no token for the target, so reads go through Postgres as the target.
 * `exists`, `info`, `list` and `listV2` run entirely there: the listings
 * call the invoker-rights `storage.search` functions storage-api calls, so
 * RLS filters each page as it would for the target's own request.
 * `download` and the signed URLs first check there that the target may see
 * the object, then the service client serves it. A hidden object answers
 * like a missing one. `getPublicUrl` is built without a check, as it is
 * built without a request.
 *
 * In a writable session, `upload`, `update`, `remove`, `copy` and `move`
 * first run the row change Storage would make as the target, inside a
 * savepoint that is rolled back, so the policies on `storage.objects`
 * decide as for the target's own request. Then the service client writes,
 * the admin connection makes the target the owner of the stored object,
 * and its `user_metadata` records the session id and the admin's id. A
 * refused dry run resolves to Storage's `403`. Signed uploads resolve to a
 * `403` `SUPPORT_STORAGE_WRITES` error, and every write in a read-only
 * session to a `403` `SUPPORT_READ_ONLY` error.
 */
export function supportStorage(options: SupportStorageOptions): StorageApi {
  const readOnly = options.readOnly ?? true;
  const { adminSql, session, sql } = options;

  const writer =
    !readOnly && adminSql && session && sql.transaction
      ? { adminSql, session }
      : undefined;

  const refusal = readOnly
    ? apiError(403, "The support session is read-only", "SUPPORT_READ_ONLY")
    : apiError(
        403,
        "Storage writes in a support session need adminSql, session and a sql client with transaction",
        "SUPPORT_STORAGE_WRITES",
      );

  const signedRefusal = readOnly
    ? refusal
    : apiError(
        403,
        "Signed uploads are not available in a support session",
        "SUPPORT_STORAGE_WRITES",
      );

  const refuse = <T>(): Promise<StorageResponse<T>> =>
    Promise.resolve(failed(refusal));

  const refuseSigned = <T>(): Promise<StorageResponse<T>> =>
    Promise.resolve(failed(signedRefusal));

  const rows = (query: string, values: unknown[]): Promise<Row[]> =>
    sql.queryRaw<Row>(query, values);

  let versioned: Promise<boolean> | undefined;

  const upsertStatement = (): Promise<string> =>
    (versioned ??= rows(CURRENT_VERSION_INDEX, [])
      .then(([row]) => row?.["versioned"] === true)
      .catch((cause: unknown) => {
        versioned = undefined;
        throw cause;
      })).then(upsertObject);

  const rehearse = async (
    run: (client: SqlClient) => Promise<StorageFailure | null>,
  ): Promise<StorageFailure | null> => {
    if (!sql.transaction) {
      return refusal;
    }

    try {
      return await sql.transaction(async (client) => {
        await client.queryRaw(`savepoint ${SAVEPOINT}`);

        try {
          return await run(client);
        } finally {
          await client.queryRaw(`rollback to savepoint ${SAVEPOINT}`);
        }
      });
    } catch (cause) {
      const refused = refusedWrite(cause);

      if (refused) {
        return refused;
      }

      throw cause;
    }
  };

  return {
    from(bucket): StorageBucketApi {
      const admin = () => options.admin.from(bucket);

      const visible = async (path: string): Promise<boolean> => {
        const [row] = await rows(VISIBLE_OBJECT, [bucket, path]);

        return row?.["visible"] === true;
      };

      const checked = <T>(
        path: string,
        read: (name: string) => PromiseLike<StorageResponse<T>>,
      ): Promise<StorageResponse<T>> =>
        settled(async () => {
          const name = normalizePath(path);

          if (!(await visible(name))) {
            return failed(NOT_FOUND);
          }

          return read(name);
        });

      const list: StorageBucketApi["list"] = (path, listOptions = {}) =>
        settled(async () => {
          const problem = listProblem(listOptions);

          if (problem) {
            return failed(invalid(problem));
          }

          let prefix = path ?? "";

          if (prefix.length > 0 && !prefix.endsWith("/")) {
            prefix = `${prefix}/`;
          }

          const column = listOptions.sortBy?.column ?? "name";
          const escape = column !== "name";
          const safePrefix = escape ? escapeLike(prefix) : prefix;
          const search = listOptions.search ?? "";
          const safeSearch = escape ? escapeLike(search) : search;

          const found = await rows(SEARCH, [
            safePrefix,
            bucket,
            listOptions.limit ?? 100,
            (safePrefix + safeSearch).split("/").length,
            listOptions.offset ?? 0,
            safeSearch,
            column,
            listOptions.sortBy?.order ?? "asc",
          ]);

          return { data: found.map(listEntryOf), error: null };
        });

      const listV2: StorageBucketApi["listV2"] = (listOptions = {}) =>
        settled(async () => {
          const problem = listV2Problem(listOptions);

          if (problem) {
            return failed(invalid(problem));
          }

          const limit = Math.min(listOptions.limit ?? 1000, 1000);
          const prefix = listOptions.prefix ?? "";

          const cursor = listOptions.cursor
            ? decodeCursor(listOptions.cursor)
            : undefined;

          if (listOptions.cursor && !cursor) {
            return failed(
              apiError(400, "Invalid continuation token", "InvalidParameter"),
            );
          }

          const sortOrder =
            filled(cursor?.sortOrder) ?? listOptions.sortBy?.order;

          const sortColumn =
            filled(cursor?.sortColumn) ?? listOptions.sortBy?.column;

          let found: Row[];

          if (listOptions.with_delimiter) {
            found = await rows(SEARCH_V2, [
              prefix,
              bucket,
              limit + 1,
              prefix ? prefix.split("/").length : 1,
              cursor?.startAfter ?? "",
              sortOrder ?? "asc",
              sortColumn ?? "name",
              filled(cursor?.sortColumnAfter) ?? null,
            ]);
          } else {
            const page = flatPage(
              bucket,
              listOptions.prefix,
              limit + 1,
              cursor,
              sortColumn,
              sortOrder,
            );

            found = await rows(page.text, page.values);
          }

          const entries = listOptions.with_delimiter
            ? delimited(found, prefix)
            : found;

          const hasNext = entries.length > limit;
          const count = hasNext ? limit : entries.length;
          const folders: StorageListV2Folder[] = [];
          const objects: StorageListV2Object[] = [];

          for (const entry of entries.slice(0, count)) {
            if (entry["id"] === null || entry["id"] === undefined) {
              folders.push(folderOf(entry));
            } else {
              objects.push(objectOf(entry));
            }
          }

          const last = entries[count - 1];

          const after =
            last && sortColumn && sortColumn !== "name"
              ? iso(last[sortColumn])
              : undefined;

          const nextCursor =
            hasNext && last
              ? encodeCursor({
                  startAfter: String(last["name"]),
                  ...(sortOrder ? { sortOrder } : {}),
                  ...(sortColumn ? { sortColumn } : {}),
                  ...(typeof after === "string"
                    ? { sortColumnAfter: new Date(after).toISOString() }
                    : {}),
                })
              : undefined;

          const data: StorageListV2Result = {
            hasNext,
            ...(nextCursor === undefined ? {} : { nextCursor }),
            folders,
            objects,
          };

          return { data, error: null };
        });

      const store =
        (method: "upload" | "update") =>
        (
          path: string,
          body: Parameters<StorageBucketApi["upload"]>[1],
          fileOptions: StorageFileOptions = {},
        ): Promise<StorageResponse<{ readonly path: string }>> => {
          if (!writer) {
            return refuse();
          }

          const { adminSql: ownerSql, session: active } = writer;

          return settled(async () => {
            const name = normalizePath(path);
            const owner = ownerOf(active.targetUserId);
            const metadata = { ...fileOptions.metadata, ...stampOf(active) };
            const upsert = method === "update" || fileOptions.upsert === true;
            const statement = upsert ? await upsertStatement() : INSERT_OBJECT;

            const refused = await rehearse(async (client) => {
              await client.queryRaw(statement, [
                bucket,
                name,
                owner,
                active.targetUserId,
                JSON.stringify(metadata),
              ]);

              return null;
            });

            if (refused) {
              return failed(refused);
            }

            const reply = await admin()[method](name, body, {
              ...fileOptions,
              metadata,
            });

            if (reply.error) {
              return reply;
            }

            try {
              await ownerSql.queryRaw(OWN_UPLOAD, [
                bucket,
                name,
                owner,
                active.targetUserId,
                active.id,
              ]);
            } catch (cause) {
              await admin().remove([name]);

              return failed(sqlFailure(cause));
            }

            return reply;
          });
        };

      const relocate =
        <T>(method: "copy" | "move") =>
        (
          from: string,
          to: string,
          destination: StorageDestinationOptions = {},
        ): Promise<StorageResponse<T>> => {
          if (!writer) {
            return refuse();
          }

          const { adminSql: ownerSql, session: active } = writer;

          return settled(async () => {
            const source = normalizePath(from);
            const name = normalizePath(to);
            const target = destination.destinationBucket ?? bucket;
            const owner = ownerOf(active.targetUserId);
            const stamp = JSON.stringify(stampOf(active));
            let previousOwner: string | null = null;

            const refused = await rehearse(async (client) => {
              const [found] = await client.queryRaw<Row>(SOURCE_OBJECT, [
                bucket,
                source,
              ]);

              if (!found) {
                return NOT_FOUND;
              }

              previousOwner = text(found["owner_id"]) ?? null;

              if (method === "copy") {
                await client.queryRaw(INSERT_OBJECT, [
                  target,
                  name,
                  owner,
                  active.targetUserId,
                  stamp,
                ]);

                return null;
              }

              const [moved] = await client.queryRaw(MOVE_OBJECT, [
                bucket,
                source,
                target,
                name,
                owner,
                active.targetUserId,
              ]);

              return moved ? null : NOT_FOUND;
            });

            if (refused) {
              return failed(refused);
            }

            // SAFETY: copy and move resolve to the reply shape their caller names as T.
            const reply = (await admin()[method](
              source,
              name,
              destination,
            )) as StorageResponse<T>;

            if (reply.error) {
              return reply;
            }

            try {
              await (method === "copy"
                ? ownerSql.queryRaw(OWN_COPY, [
                    target,
                    name,
                    owner,
                    active.targetUserId,
                    stamp,
                  ])
                : ownerSql.queryRaw(OWN_MOVE, [
                    target,
                    name,
                    owner,
                    active.targetUserId,
                    stamp,
                    previousOwner,
                  ]));
            } catch (cause) {
              const written = options.admin.from(target);
              await (method === "copy"
                ? written.remove([name])
                : written.move(name, source, { destinationBucket: bucket }));

              return failed(sqlFailure(cause));
            }

            return reply;
          });
        };

      const remove = (
        paths: StorageRemoveEntry[],
      ): Promise<StorageResponse<readonly StorageListEntry[]>> => {
        if (!writer) {
          return refuse();
        }

        return settled(async () => {
          const entries = paths.map((entry) =>
            typeof entry === "string"
              ? normalizePath(entry)
              : { ...entry, path: normalizePath(entry.path) },
          );

          const names = entries.map((entry) =>
            typeof entry === "string" ? entry : entry.path,
          );

          const removable = new Set<string>();

          const refused = await rehearse(async (client) => {
            await client.queryRaw(ALLOW_DELETE);

            const deleted = await client.queryRaw(DELETE_OBJECTS, [
              bucket,
              [...new Set(names)],
            ]);

            for (const row of deleted) {
              removable.add(String(row["name"]));
            }

            return null;
          });

          if (refused) {
            return failed(refused);
          }

          const permitted = entries.filter((_, index) =>
            removable.has(names[index] ?? ""),
          );

          if (permitted.length === 0) {
            return { data: [], error: null };
          }

          return admin().remove(permitted);
        });
      };

      return {
        exists: (path) =>
          settled<boolean>(async () => ({
            data: await visible(normalizePath(path)),
            error: null,
          })).then((reply) =>
            reply.error === null ? reply : { data: false, error: reply.error },
          ),
        info: (path, infoOptions) =>
          settled(async () => {
            const versionId = infoOptions?.versionId;
            const name = normalizePath(path);

            const [row] = await rows(
              versionId === undefined
                ? OBJECT_INFO
                : `${OBJECT_INFO} and o.version = $3`,
              versionId === undefined
                ? [bucket, name]
                : [bucket, name, versionId],
            );

            const object = row?.["object"];

            return isRecord(object)
              ? { data: infoOf(object), error: null }
              : failed(NOT_FOUND);
          }),
        download: (path, downloadOptions, parameters) =>
          checked(path, (name) =>
            admin().download(name, downloadOptions, parameters),
          ),
        createSignedUrl: (path, expiresIn, urlOptions) =>
          checked(path, (name) =>
            admin().createSignedUrl(name, expiresIn, urlOptions),
          ),
        createSignedUrls: (paths, expiresIn, urlOptions) =>
          settled(async () => {
            const names = paths.map(normalizePath);

            const seen = new Set(
              (await rows(VISIBLE_OBJECTS, [bucket, names])).map((row) =>
                String(row["path"]),
              ),
            );

            const shown = [...new Set(names.filter((name) => seen.has(name)))];
            const signed = new Map<string, StorageSignedUrlEntry>();

            if (shown.length > 0) {
              const reply = await admin().createSignedUrls(
                shown,
                expiresIn,
                urlOptions,
              );

              if (reply.error) {
                return failed(reply.error);
              }

              for (const entry of reply.data) {
                if (entry.path !== null) {
                  signed.set(entry.path, entry);
                }
              }
            }

            const data = names.map(
              (name): StorageSignedUrlEntry =>
                signed.get(name) ?? {
                  error: HIDDEN_URL,
                  path: name,
                  signedUrl: null,
                },
            );

            return { data, error: null };
          }),
        getPublicUrl: (path, urlOptions) =>
          admin().getPublicUrl(path, urlOptions),
        list,
        listV2,
        upload: store("upload"),
        update: store("update"),
        createSignedUploadUrl: refuseSigned,
        uploadToSignedUrl: refuseSigned,
        remove,
        copy: relocate<{ readonly path: string }>("copy"),
        move: relocate<{ readonly message: string }>("move"),
        purgeCache: (path, cacheOptions, parameters) =>
          writer
            ? checked(path, (name) =>
                admin().purgeCache(name, cacheOptions, parameters),
              )
            : refuse(),
      };
    },
  };
}
