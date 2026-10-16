import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { Logger } from "../../core/logger.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError, type ErrorMapper } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { fromStorageError } from "../../storage/errors.ts";
import {
  applyTemporal,
  blockCall,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  stringsOf,
  textOf,
  toInstant,
  type BlockTemporalOptions,
} from "../shared.ts";

interface StorageReply<T> {
  readonly data: T | null;
  readonly error: unknown;
}

/** An entry of `storage.from(bucket).list(prefix)`; folders have no `id`. */
export interface StorageEntry {
  readonly name: string;
  readonly id: string | null;
}

/** The `supabase.storage.from(bucket)` methods the lifecycle blocks use. */
export interface LifecycleBucket {
  upload(
    path: string,
    body: Blob,
    options?: { contentType?: string; upsert?: boolean },
  ): PromiseLike<StorageReply<unknown>>;
  createSignedUrl(
    path: string,
    expiresIn: number,
    options?: { download?: string | boolean },
  ): PromiseLike<StorageReply<{ readonly signedUrl: string }>>;
  list(
    path?: string,
    options?: { limit?: number; offset?: number },
  ): PromiseLike<StorageReply<readonly StorageEntry[]>>;
  remove(paths: string[]): PromiseLike<StorageReply<unknown>>;
}

/** `supabase.storage`, typed structurally. */
export interface LifecycleStorage {
  from(bucket: string): LifecycleBucket;
}

export type DataExportStatus = "pending" | "running" | "ready" | "failed";

export interface DataExport {
  readonly id: string;
  readonly subject: "user" | "organization";
  readonly userId: string | undefined;
  readonly organizationId: string | undefined;
  readonly status: DataExportStatus;
  readonly bucket: string;
  /** Object paths, one file per table: `{id}/{schema.table}.ndjson` (or `.csv`). */
  readonly files: readonly string[];
  readonly error: string | undefined;
  readonly requestedBy: string | undefined;
  readonly requestedAt: Temporal.Instant;
  readonly completedAt: Temporal.Instant | undefined;
  /** After this the files are no longer served. */
  readonly expiresAt: Temporal.Instant | undefined;
}

export interface OrganizationDeletion {
  readonly organizationId: string;
  readonly requestedBy: string | undefined;
  readonly requestedAt: Temporal.Instant;
  readonly purgeAfter: Temporal.Instant;
  readonly cancelledAt: Temporal.Instant | undefined;
  readonly purgedAt: Temporal.Instant | undefined;
}

export interface DataExportDownload {
  readonly export: DataExport;
  /** One signed URL per file, keyed by the table it holds. */
  readonly files: readonly { readonly table: string; readonly url: string }[];
}

export interface DataLifecycleOptions extends BlockTemporalOptions {
  /** The caller's transport (`rpcTransport(supabase)`). */
  readonly transport: BlockTransport;
  /** The caller's `supabase.storage`, for `download`. */
  readonly storage?: LifecycleStorage;
  /** The module schema, or its API schema: `defineBlocks` passes it from `blocks.generated.ts`. Default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /** Lifetime of a signed download URL in seconds. Default 300. */
  readonly downloadTtl?: number;
  /** `withBlockHooks` hooks around the methods (ADR 0015). */
  readonly hooks?: NoInfer<BlockHooks<DataLifecycle>>;
  /** Receives the errors `after` hooks throw. */
  readonly logger?: Logger;
}

export interface DataLifecycle {
  /** Exports the caller's data, or a tenant's with `organizationId` (needs `organization.export`). */
  requestExport(options?: {
    readonly organizationId?: string;
  }): AsyncResult<DataExport>;
  /** The caller's exports, or a tenant's, newest first. */
  exports(organizationId?: string): AsyncResult<readonly DataExport[]>;
  /** Signed URLs for a ready export's files. */
  download(exportId: string): AsyncResult<DataExportDownload>;
  /**
   * Disables the tenant and schedules its purge after `grace` (an
   * interval such as `30 days` or a `Temporal.Duration`; default the
   * module's `grace` option). Needs `organization.delete`.
   */
  requestOrganizationDeletion(
    organizationId: string,
    options?: { readonly grace?: Temporal.Duration | string },
  ): AsyncResult<OrganizationDeletion>;
  /** The requester or an owner cancels; `undefined` when nothing is pending. */
  cancelOrganizationDeletion(
    organizationId: string,
  ): AsyncResult<OrganizationDeletion | undefined>;
  /** The pending deletion, for members of the organization. */
  organizationDeletion(
    organizationId: string,
  ): AsyncResult<OrganizationDeletion | undefined>;
}

const EXPORT_STATUSES: readonly DataExportStatus[] = [
  "pending",
  "running",
  "ready",
  "failed",
];

export function exportOf(value: unknown): DataExport {
  const row = recordOf(value, "data_exports");
  const status = EXPORT_STATUSES.find(
    (candidate) => candidate === row["status"],
  );
  if (status === undefined) {
    throw new TypeError(
      `Unknown export status ${JSON.stringify(row["status"])}`,
    );
  }
  return {
    id: textOf(row["id"]),
    subject: row["subject"] === "organization" ? "organization" : "user",
    userId: optionalText(row["user_id"]),
    organizationId: optionalText(row["organization_id"]),
    status,
    bucket: textOf(row["bucket"]),
    files: stringsOf(row["files"]),
    error: optionalText(row["error"]),
    requestedBy: optionalText(row["requested_by"]),
    requestedAt: toInstant(textOf(row["requested_at"])),
    completedAt: optionalInstant(row["completed_at"]),
    expiresAt: optionalInstant(row["expires_at"]),
  };
}

export function deletionOf(value: unknown): OrganizationDeletion {
  const row = recordOf(value, "organization_deletions");
  return {
    organizationId: textOf(row["organization_id"]),
    requestedBy: optionalText(row["requested_by"]),
    requestedAt: toInstant(textOf(row["requested_at"])),
    purgeAfter: toInstant(textOf(row["purge_after"])),
    cancelledAt: optionalInstant(row["cancelled_at"]),
    purgedAt: optionalInstant(row["purged_at"]),
  };
}

const optionalDeletion = (value: unknown): OrganizationDeletion | undefined =>
  isRecord(value) ? deletionOf(value) : undefined;

export function stored<T>(
  reply: PromiseLike<StorageReply<T>>,
): AsyncResult<NonNullable<T>> {
  return AsyncResult.from(async () => {
    try {
      const { data, error } = await reply;
      if (error) return err(fromStorageError(error, "storage.objects"));
      if (data === null || data === undefined) {
        return err(dbError("network", "Storage returned no data"));
      }
      return ok(data);
    } catch (cause) {
      return err(fromStorageError(cause, "storage.objects"));
    }
  });
}

/** The table a file holds: `{id}/public.projects.ndjson` gives `public.projects`. */
const tableOf = (path: string): string =>
  path.slice(path.lastIndexOf("/") + 1).replace(/\.(ndjson|csv)$/, "");

/** Exports and organization deletion as the caller. */
export function createDataLifecycle(
  options: DataLifecycleOptions,
): DataLifecycle {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const ttl = options.downloadTtl ?? 300;
  const client: DataLifecycle = {
    requestExport: (request = {}) =>
      call(
        "request_data_export",
        request.organizationId === undefined
          ? { subject: "user" }
          : { subject: "organization", tenant: request.organizationId },
        exportOf,
      ),
    exports: (organizationId) =>
      call("list_data_exports", { tenant: organizationId }, (value) =>
        recordsOf(value, "list_data_exports").map(exportOf),
      ),
    download: (exportId) =>
      call("get_data_export", { id: exportId }, (value) => value).andThen(
        async (value) => {
          if (!isRecord(value)) {
            return err(
              dbError("not_found", "No export you can see has this id", {
                hint: "DATA_EXPORT_NOT_FOUND",
              }),
            );
          }
          const found = exportOf(value);
          if (found.status !== "ready") {
            return err(
              dbError("invalid_request", "The export is not ready", {
                hint: "DATA_EXPORT_NOT_READY",
              }),
            );
          }
          if (!options.storage) {
            return err(
              dbError(
                "invalid_request",
                "Pass storage to createDataLifecycle to download exports",
              ),
            );
          }
          const bucket = options.storage.from(found.bucket);
          const files: { table: string; url: string }[] = [];
          for (const path of found.files) {
            const signed = await stored(
              bucket.createSignedUrl(path, ttl, { download: true }),
            );
            if (!signed.ok) return signed;
            files.push({ table: tableOf(path), url: signed.data.signedUrl });
          }
          return ok({ export: found, files });
        },
      ),
    requestOrganizationDeletion: (organizationId, request = {}) =>
      call(
        "request_organization_deletion",
        {
          tenant: organizationId,
          grace:
            request.grace === undefined ? undefined : String(request.grace),
        },
        deletionOf,
      ),
    cancelOrganizationDeletion: (organizationId) =>
      call(
        "cancel_organization_deletion",
        { tenant: organizationId },
        optionalDeletion,
      ),
    organizationDeletion: (organizationId) =>
      call(
        "organization_deletion",
        { tenant: organizationId },
        optionalDeletion,
      ),
  };
  return withBlockHooks(client, options.hooks, {
    block: "data-lifecycle",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
