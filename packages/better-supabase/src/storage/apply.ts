import type { StorageClient } from "./bucket.ts";

import { AsyncResult, err, ok } from "../core/result.ts";
import { fromStorageError } from "./errors.ts";
import {
  lifecycleAbsent,
  type LifecyclePayload,
  type VersioningStatus,
} from "./versioning.ts";

export interface BucketSettings {
  readonly id: string;
  readonly public: boolean;
  readonly fileSizeLimit: number | undefined;
  readonly allowedMimeTypes: readonly string[] | undefined;
  readonly versioning: boolean;
  readonly lifecycle: LifecyclePayload | undefined;
}

export interface AppliedBucket {
  /** The bucket did not exist and was created. */
  readonly created: boolean;
}

/**
 * Creates or updates a bucket through the Storage API, then sets or removes
 * its lifecycle policy. Versioning and lifecycle live behind the API, so
 * `bucket.sql()` can't write them.
 */
export function applyBucket(
  settings: BucketSettings,
  client: StorageClient,
): AsyncResult<AppliedBucket> {
  const storage = client.storage;
  const fail = (raw: unknown) => err(fromStorageError(raw, settings.id));
  return AsyncResult.from(async () => {
    try {
      const limits = {
        public: settings.public,
        fileSizeLimit: settings.fileSizeLimit ?? null,
        allowedMimeTypes: settings.allowedMimeTypes
          ? [...settings.allowedMimeTypes]
          : null,
      };
      const found = await storage.getBucket(settings.id);
      const missing =
        found.error !== null &&
        fromStorageError(found.error).kind === "not_found";
      if (found.error && !missing) return fail(found.error);
      if (missing) {
        const created = await storage.createBucket(settings.id, {
          ...limits,
          ...(settings.versioning ? { versioningStatus: "ENABLED" } : {}),
        });
        if (created.error) return fail(created.error);
      } else {
        // `versioning_status` is absent on Storage versions without versioning.
        const current: VersioningStatus | undefined =
          found.data?.versioning_status;
        const versioningStatus = settings.versioning
          ? "ENABLED"
          : current === "ENABLED"
            ? "SUSPENDED"
            : undefined;
        const updated = await storage.updateBucket(settings.id, {
          ...limits,
          ...(versioningStatus ? { versioningStatus } : {}),
        });
        if (updated.error) return fail(updated.error);
      }
      if (settings.lifecycle) {
        const set = await storage.updateBucketLifecycle(settings.id, {
          rules: settings.lifecycle.rules.map((rule) => ({ ...rule })),
        });
        if (set.error) return fail(set.error);
      } else if (!missing) {
        const removed = await storage.deleteBucketLifecycle(settings.id);
        if (removed.error && !lifecycleAbsent(fromStorageError(removed.error)))
          return fail(removed.error);
      }
      return ok({ created: missing });
    } catch (cause) {
      return fail(cause);
    }
  });
}
