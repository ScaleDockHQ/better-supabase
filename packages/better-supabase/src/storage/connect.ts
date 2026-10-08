import type { DbError } from "../core/errors.ts";
import type { TemplateValues } from "../core/template.ts";
import type {
  Bucket,
  BucketClient,
  BucketConnectOptions,
  ObjectTarget,
  ReplaceResult,
  StorageClient,
  StoredObject,
  UploadBody,
  UploadOptions,
  UrlOptions,
} from "./bucket.ts";
import type { StoragePath } from "./path.ts";
import type { TenantGuard } from "./tenant-scope.ts";

import { DbException, dbError } from "../core/errors.ts";
import { AsyncResult, err, ok, toDbError } from "../core/result.ts";
import { temporalMissing } from "../core/temporal-required.ts";
import { optionalTemporal } from "../core/temporal.ts";
import { fromStorageError } from "./errors.ts";
import { inScope } from "./layouts.ts";
import { ttlSeconds } from "./ttl.ts";
import { type ObjectVersion, toVersion } from "./versioning.ts";

/** Folder listings in flight at once while `list` walks a tree. */
const LIST_CONCURRENCY = 4;
/** Signed URLs kept per connected bucket; the oldest goes first. */
const SIGNED_CACHE_SIZE = 500;

/** Runs at most `limit` of the calls passed to the returned function at once. */
function pool(limit: number): <T>(fn: () => Promise<T>) => Promise<T> {
  let active = 0;
  const waiting: (() => void)[] = [];
  return async (fn) => {
    if (active < limit) active++;
    else
      await new Promise<void>((resolve) => {
        waiting.push(resolve);
      });
    try {
      return await fn();
    } finally {
      const next = waiting.shift();
      if (next) next();
      else active--;
    }
  };
}

function bodyInfo(
  body: UploadBody,
  contentType: string | undefined,
): { size?: number; type?: string } {
  const info: { size?: number; type?: string } = {};
  if (typeof Blob !== "undefined" && body instanceof Blob) {
    info.size = body.size;
    if (body.type) info.type = body.type;
  } else if (body instanceof ArrayBuffer || ArrayBuffer.isView(body)) {
    info.size = body.byteLength;
  }
  if (contentType) info.type = contentType;
  return info;
}

/** Rejects with the signal's reason when it aborts before `promise` settles. */
function abortable<T>(
  promise: PromiseLike<T>,
  signal: AbortSignal | undefined,
): PromiseLike<T> {
  if (!signal) return promise;
  return new Promise<T>((resolve, reject) => {
    const abort = () => reject(signal.reason);
    if (signal.aborted) return abort();
    signal.addEventListener("abort", abort, { once: true });
    promise.then(
      (value) => {
        signal.removeEventListener("abort", abort);
        resolve(value);
      },
      (cause: unknown) => {
        signal.removeEventListener("abort", abort);
        reject(cause);
      },
    );
  });
}

function isErrorResult(value: unknown): value is { ok: false; error: DbError } {
  // SAFETY: value is a non-null object here, and each property read is type-checked.
  return (
    typeof value === "object" &&
    value !== null &&
    (value as { ok?: unknown }).ok === false &&
    "error" in value
  );
}

export function connectBucket<P extends string, Id extends string>(
  bucket: Bucket<P, Id>,
  client: StorageClient,
  resolveTarget: (target: ObjectTarget<P, Id>) => StoragePath<Id>,
  connectOptions: BucketConnectOptions,
  guard: TenantGuard | undefined,
): BucketClient<P, Id> {
  const resolve = (target: ObjectTarget<P, Id>): StoragePath<Id> => {
    const path = resolveTarget(target);
    return guard ? guard.path(path) : path;
  };
  const scopedWithin = (
    within: Partial<TemplateValues<P>> | undefined,
  ): Partial<TemplateValues<P>> =>
    guard ? { ...within, [guard.param]: guard.within(within) } : (within ?? {});
  const api = () => client.storage.from(bucket.id);
  const signed = connectOptions.cacheSignedUrls
    ? new Map<string, { readonly url: string; readonly until: number }>()
    : undefined;
  /** Drops cached signed URLs for `paths`; keys start with the JSON-quoted path. */
  const evict = (paths: readonly string[]) => {
    if (!signed || signed.size === 0) return;
    const prefixes = paths.map((path) => `[${JSON.stringify(path)},`);
    for (const key of signed.keys())
      if (prefixes.some((prefix) => key.startsWith(prefix))) signed.delete(key);
  };
  const run = <T>(
    fn: () => PromiseLike<{ data: T; error: unknown }>,
  ): AsyncResult<NonNullable<T>> =>
    AsyncResult.from(async () => {
      try {
        const { data, error } = await fn();
        // SAFETY: the null check above excludes null data.
        return error || data === null
          ? err(fromStorageError(error, bucket.id))
          : ok(data as NonNullable<T>);
      } catch (cause) {
        return err(fromStorageError(cause, bucket.id));
      }
    });
  const fileOptions = (
    options: UploadOptions | undefined,
    contentType: string | undefined,
  ) => ({
    ...(contentType ? { contentType } : {}),
    ...(options?.cacheControl ? { cacheControl: options.cacheControl } : {}),
    ...(options?.metadata ? { metadata: { ...options.metadata } } : {}),
    upsert: options?.upsert ?? false,
  });
  const download = (value: boolean | string | undefined) =>
    value === undefined ? {} : { download: value };
  const urlExtras = (options: Omit<UrlOptions, "ttl"> | undefined) => ({
    ...download(options?.download),
    ...(options?.transform ? { transform: { ...options.transform } } : {}),
    ...(options?.cacheNonce ? { cacheNonce: options.cacheNonce } : {}),
    ...(options?.versionId ? { versionId: options.versionId } : {}),
  });

  const upload: BucketClient<P, Id>["upload"] = (target, body, options) =>
    AsyncResult.from(async () => {
      options?.signal?.throwIfAborted();
      const path = resolve(target);
      const contentType = options?.contentType;
      const problem = bucket.check(bodyInfo(body, contentType));
      if (problem) return err(problem);
      // storage-js `upload` takes no signal, so an abort settles the result
      // early instead of cancelling the request.
      return run(() =>
        abortable(
          api().upload(path, body, fileOptions(options, contentType)),
          options?.signal,
        ),
      ).map(() => {
        evict([path]);
        return { path };
      });
    });

  const remove: BucketClient<P, Id>["remove"] = (targets) =>
    AsyncResult.from(async () => {
      const paths = targets.map(resolve);
      if (paths.length === 0) return ok([]);
      return run(() => api().remove(paths)).map(() => {
        evict(paths);
        return paths;
      });
    });

  const transfer =
    (method: "copy" | "move"): BucketClient<P, Id>["copy"] =>
    (from, to, options) =>
      AsyncResult.from(async () => {
        const [source, path] = [resolve(from), resolve(to)];
        const result = run<unknown>(() =>
          api()[method](
            source,
            path,
            options?.versionId
              ? { sourceVersionId: options.versionId }
              : undefined,
          ),
        );
        return result.map(() => {
          evict(method === "move" ? [source, path] : [path]);
          return { path };
        });
      });

  const versions: BucketClient<P, Id>["versions"] = (target, options) =>
    AsyncResult.from(async () => {
      const path = resolve(target);
      const out: ObjectVersion[] = [];
      for (let cursor: string | undefined; ;) {
        options?.signal?.throwIfAborted();
        const { data, error } = await api().listV2(
          {
            prefix: path,
            exactMatch: true,
            noncurrentVersions: "include",
            deleteMarkers: "include",
            sortBy: { column: "created_at", order: "desc" },
            ...(cursor ? { cursor } : {}),
          },
          options?.signal ? { signal: options.signal } : {},
        );
        if (error) return err(fromStorageError(error, bucket.id));
        for (const item of data.objects) {
          const version = toVersion(item);
          if (version) out.push(version);
        }
        if (!data.hasNext || !data.nextCursor) return ok(out);
        cursor = data.nextCursor;
      }
    });

  type Listed = {
    name: string;
    id: string | null;
    metadata: unknown;
    created_at: string;
    updated_at: string;
  };
  const toObject = (path: string, item: Listed): StoredObject => {
    // SAFETY: Storage returns object metadata as JSON with optional size
    // and type fields.
    const metadata = (item.metadata ?? {}) as {
      size?: number;
      mimetype?: string;
    };
    return {
      path,
      ...(typeof metadata.size === "number" ? { size: metadata.size } : {}),
      ...(metadata.mimetype ? { contentType: metadata.mimetype } : {}),
      createdAt: item.created_at,
      updatedAt: item.updated_at,
    };
  };
  const PAGE = 1000;
  const page = async (
    folder: string,
    offset: number,
    signal: AbortSignal | undefined,
  ): Promise<readonly Listed[]> => {
    signal?.throwIfAborted();
    const { data, error } = await api().list(
      folder,
      { limit: PAGE, offset, sortBy: { column: "name", order: "asc" } },
      signal ? { signal } : {},
    );
    if (error) throw new DbException(fromStorageError(error, bucket.id));
    return data;
  };

  const walk = async (
    folder: string,
    signal: AbortSignal | undefined,
    request: <T>(fn: () => Promise<T>) => Promise<T>,
  ): Promise<StoredObject[]> => {
    const parts: (StoredObject | Promise<StoredObject[]>)[] = [];
    for (let offset = 0; ; offset += PAGE) {
      const data = await request(() => page(folder, offset, signal));
      for (const item of data) {
        const path = folder ? `${folder}/${item.name}` : item.name;
        if (item.id === null) {
          const nested = walk(path, signal, request);
          // Awaited below in order; this only keeps an early failure from
          // going unhandled while an earlier sibling is still pending.
          nested.catch(() => undefined);
          parts.push(nested);
        } else parts.push(toObject(path, item));
      }
      if (data.length < PAGE) break;
    }
    const out: StoredObject[] = [];
    for (const part of parts) {
      if (part instanceof Promise)
        for (const each of await part) out.push(each);
      else out.push(part);
    }
    return out;
  };

  /** Yields objects one listing page at a time, depth first, in `list` order. */
  async function* stream(
    folder: string,
    signal: AbortSignal | undefined,
  ): AsyncGenerator<StoredObject> {
    for (let offset = 0; ; offset += PAGE) {
      const data = await page(folder, offset, signal);
      for (const item of data) {
        const path = folder ? `${folder}/${item.name}` : item.name;
        if (item.id === null) yield* stream(path, signal);
        else yield toObject(path, item);
      }
      if (data.length < PAGE) return;
    }
  }

  const list: BucketClient<P, Id>["list"] = (within, options) =>
    AsyncResult.from(async () =>
      ok(
        await walk(
          bucket.prefix(scopedWithin(within)),
          options?.signal,
          pool(LIST_CONCURRENCY),
        ),
      ),
    ).mapError((error) => ({ ...error, table: bucket.id }));

  const signedUrl: BucketClient<P, Id>["signedUrl"] = (target, options) =>
    AsyncResult.from(async () => {
      const path = resolve(target);
      const ttl = ttlSeconds(options?.ttl);
      const key = signed
        ? JSON.stringify([
            path,
            ttl,
            options?.transform,
            options?.download,
            options?.cacheNonce,
            options?.versionId,
          ])
        : "";
      const cached = signed?.get(key);
      if (cached) {
        if (cached.until > Date.now()) return ok(cached.url);
        signed?.delete(key);
      }
      const result = await run(() =>
        api().createSignedUrl(path, ttl, urlExtras(options)),
      ).map((data) => data.signedUrl);
      if (signed && result.ok) {
        const margin = Math.min(60, ttl / 10);
        if (signed.size >= SIGNED_CACHE_SIZE) {
          const oldest = signed.keys().next();
          if (!oldest.done) signed.delete(oldest.value);
        }
        signed.set(key, {
          url: result.data,
          until: Date.now() + (ttl - margin) * 1000,
        });
      }
      return result;
    });

  return {
    bucket,
    path: (target) => {
      try {
        return ok(resolve(target));
      } catch (cause) {
        return err(toDbError(cause));
      }
    },
    upload,
    download: (target, options) =>
      AsyncResult.from(async () => {
        const path = resolve(target);
        return run(() =>
          api().download(
            path,
            options?.versionId ? { versionId: options.versionId } : {},
            options?.signal ? { signal: options.signal } : {},
          ),
        );
      }),
    exists: (target) =>
      AsyncResult.from(async () => {
        const path = resolve(target);
        let found: { data: boolean; error: unknown };
        try {
          found = await api().exists(path);
        } catch (cause) {
          return err(fromStorageError(cause, bucket.id));
        }
        if (found.data && !found.error) return ok(true);
        if (!found.error) return ok(false);
        // Only a 400 or 404 means missing; a denied or failed check is an error.
        const error = fromStorageError(found.error, bucket.id);
        return error.status === 400 || error.status === 404
          ? ok(false)
          : err(error);
      }),
    remove,
    copy: transfer("copy"),
    move: transfer("move"),
    versions,
    removeVersions: (target, versionIds) =>
      AsyncResult.from(async () => {
        const path = resolve(target);
        if (versionIds.length === 0) return ok([]);
        return run(() =>
          api().remove(versionIds.map((versionId) => ({ path, versionId }))),
        ).map(() => {
          evict([path]);
          return versionIds;
        });
      }),
    purgeCache: (target, options) =>
      AsyncResult.from(async () => {
        const path = resolve(target);
        return run(() =>
          api().purgeCache(
            path,
            options?.transformations ? { transformations: true } : {},
            options?.signal ? { signal: options.signal } : {},
          ),
        ).map(() => undefined);
      }),
    list,
    signedUrl,
    signedUrls: (targets, options) =>
      AsyncResult.from(async () => {
        const paths = targets.map(resolve);
        if (paths.length === 0) return ok([]);
        return run(() =>
          api().createSignedUrls(paths, ttlSeconds(options?.ttl), {
            ...download(options?.download),
            ...(options?.cacheNonce ? { cacheNonce: options.cacheNonce } : {}),
          }),
        ).andThen((data) => {
          const failed = data.find(
            (entry) => entry.error != null || !entry.signedUrl,
          );
          if (failed)
            return Promise.resolve(
              err(
                dbError(
                  "not_found",
                  failed.error ?? `No URL for ${String(failed.path)}`,
                  { table: bucket.id },
                ),
              ),
            );
          // SAFETY: the failure check above returned early, so every entry has
          // a signed URL.
          return Promise.resolve(ok(data.map((entry) => entry.signedUrl!)));
        });
      }),
    publicUrl(target, options) {
      try {
        return ok(
          api().getPublicUrl(resolve(target), urlExtras(options)).data
            .publicUrl,
        );
      } catch (cause) {
        return err(toDbError(cause));
      }
    },
    renderUrl(target, transform, options) {
      if (!bucket.public) return signedUrl(target, { ...options, transform });
      return AsyncResult.from(() =>
        Promise.resolve(
          ok(
            api().getPublicUrl(
              resolve(target),
              urlExtras({ ...options, transform }),
            ).data.publicUrl,
          ),
        ),
      );
    },
    replace: (target, body, options = {}) =>
      AsyncResult.from<ReplaceResult<Id>>(async () => {
        const path = resolve(target);
        const previous =
          options.previous == null ? null : resolve(options.previous);
        const same = previous === path;
        const uploaded = await upload(path, body, {
          ...options,
          upsert: same || (options.upsert ?? false),
        });
        if (!uploaded.ok) return uploaded;
        const undo = async (error: DbError) => {
          if (!same) await remove([path]);
          return err(error);
        };
        try {
          options.signal?.throwIfAborted();
          const outcome: unknown = await options.commit?.(path);
          if (isErrorResult(outcome)) return await undo(outcome.error);
        } catch (cause) {
          return undo(fromStorageError(cause, bucket.id));
        }
        if (!previous || same) return ok({ path, removed: null });
        const removed = await run(() => api().remove([previous]));
        if (removed.ok) evict([previous]);
        return ok(
          removed.ok
            ? { path, removed: previous }
            : { path, removed: null, cleanup: removed.error },
        );
      }),
    reserve: (target, options) =>
      AsyncResult.from(async () => {
        const path = resolve(target);
        return run(() =>
          api().createSignedUploadUrl(
            path,
            options?.upsert ? { upsert: true } : undefined,
          ),
        ).map((data) => ({
          path: data.path,
          token: data.token,
          signedUrl: data.signedUrl,
        }));
      }),
    uploadReserved: (reservation, body, options) =>
      AsyncResult.from(async () => {
        options?.signal?.throwIfAborted();
        const path = resolve(reservation.path);
        const problem = bucket.check(bodyInfo(body, options?.contentType));
        if (problem) return err(problem);
        return run(() =>
          api().uploadToSignedUrl(
            path,
            reservation.token,
            body,
            fileOptions(options, options?.contentType),
          ),
        ).map(() => {
          evict([path]);
          return { path };
        });
      }),
    sweep: (options) =>
      AsyncResult.from(async () => {
        const namespace = optionalTemporal();
        if (namespace === undefined) return err(temporalMissing());
        const now = options.now?.() ?? namespace.Now.instant();
        const cutoff =
          options.olderThan instanceof namespace.Instant
            ? options.olderThan.epochMilliseconds
            : now.epochMilliseconds - options.olderThan.total("milliseconds");
        const scope = scopedWithin(options.within);
        const size = options.batchSize ?? 100;
        const orphans: string[] = [];
        const removed: string[] = [];
        let scanned = 0;
        let batch: string[] = [];
        const check = async () => {
          options.signal?.throwIfAborted();
          const keep = new Set(await options.referenced(batch));
          for (const path of batch) if (!keep.has(path)) orphans.push(path);
          batch = [];
        };
        try {
          for await (const object of stream(
            bucket.prefix(scope),
            options.signal,
          )) {
            scanned++;
            if (!inScope(bucket.match(object.path), scope)) continue;
            // Storage sends ISO text; epoch milliseconds compare directly.
            const created = Date.parse(
              object.createdAt ?? object.updatedAt ?? "",
            );
            if (!Number.isFinite(created) || created >= cutoff) continue;
            batch.push(object.path);
            if (batch.length >= size) await check();
          }
          if (batch.length > 0) await check();
        } catch (cause) {
          return err({ ...toDbError(cause), table: bucket.id });
        }
        // Removing only after the walk keeps offset paging from skipping
        // objects that shift into an already listed page.
        for (let index = 0; index < orphans.length && !options.dryRun;) {
          options.signal?.throwIfAborted();
          const chunk = orphans.slice(index, index + size);
          const result = await run(() => api().remove(chunk));
          if (!result.ok) return result;
          evict(chunk);
          removed.push(...chunk);
          index += size;
        }
        return ok({ scanned, orphans, removed });
      }),
  };
}
