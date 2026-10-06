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
      return run(() =>
        api().upload(path, body, fileOptions(options, contentType)),
      ).map(() => ({ path }));
    });

  const remove: BucketClient<P, Id>["remove"] = (targets) =>
    AsyncResult.from(async () => {
      const paths = targets.map(resolve);
      if (paths.length === 0) return ok([]);
      return run(() => api().remove(paths)).map(() => paths);
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
        return result.map(() => ({ path }));
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

  const walk = async (
    folder: string,
    signal: AbortSignal | undefined,
    out: StoredObject[],
  ) => {
    const limit = 1000;
    for (let offset = 0; ; offset += limit) {
      signal?.throwIfAborted();
      const { data, error } = await api().list(
        folder,
        { limit, offset, sortBy: { column: "name", order: "asc" } },
        signal ? { signal } : {},
      );
      if (error) throw new DbException(fromStorageError(error, bucket.id));
      for (const item of data) {
        const path = folder ? `${folder}/${item.name}` : item.name;
        if (item.id === null) await walk(path, signal, out);
        else {
          // SAFETY: Storage returns object metadata as JSON with optional size
          // and type fields.
          const metadata = (item.metadata ?? {}) as {
            size?: number;
            mimetype?: string;
          };
          out.push({
            path,
            ...(typeof metadata.size === "number"
              ? { size: metadata.size }
              : {}),
            ...(metadata.mimetype ? { contentType: metadata.mimetype } : {}),
            createdAt: item.created_at,
            updatedAt: item.updated_at,
          });
        }
      }
      if (data.length < limit) return;
    }
  };

  const list: BucketClient<P, Id>["list"] = (within, options) =>
    AsyncResult.from(async () => {
      const out: StoredObject[] = [];
      await walk(bucket.prefix(scopedWithin(within)), options?.signal, out);
      return ok(out);
    }).mapError((error) => ({ ...error, table: bucket.id }));

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
      if (cached && cached.until > Date.now()) return ok(cached.url);
      const result = await run(() =>
        api().createSignedUrl(path, ttl, urlExtras(options)),
      ).map((data) => data.signedUrl);
      if (signed && result.ok) {
        const margin = Math.min(60, ttl / 10);
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
        const found = await api().exists(path);
        if (!found.data) return ok(false);
        return found.error
          ? err(fromStorageError(found.error, bucket.id))
          : ok(true);
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
        ).map(() => versionIds);
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
        ).map(() => ({ path }));
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
        const found = await list(
          options.within,
          options.signal ? { signal: options.signal } : undefined,
        );
        if (!found.ok) return found;
        const scope = scopedWithin(options.within);
        const candidates = found.data
          .filter((object) => inScope(bucket.match(object.path), scope))
          .filter((object) => {
            // Storage sends ISO text; epoch milliseconds compare directly.
            const created = Date.parse(
              object.createdAt ?? object.updatedAt ?? "",
            );
            return Number.isFinite(created) && created < cutoff;
          })
          .map((object) => object.path);
        const size = options.batchSize ?? 100;
        const orphans: string[] = [];
        const removed: string[] = [];
        for (let index = 0; index < candidates.length; index += size) {
          options.signal?.throwIfAborted();
          const batch = candidates.slice(index, index + size);
          const keep = new Set(await options.referenced(batch));
          const unreferenced = batch.filter((path) => !keep.has(path));
          orphans.push(...unreferenced);
          if (options.dryRun || unreferenced.length === 0) continue;
          const result = await run(() => api().remove(unreferenced));
          if (!result.ok) return result;
          removed.push(...unreferenced);
        }
        return ok({ scanned: found.data.length, orphans, removed });
      }),
  };
}
