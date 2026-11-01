import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
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

export type DataExportFormat = "ndjson" | "csv";

export interface DataExport {
  readonly id: string;
  /** `record` is one `config.subjects` record, from `requestSubjectExport`. */
  readonly subject: "user" | "organization" | "record";
  readonly userId: string | undefined;
  readonly organizationId: string | undefined;
  /** Subject `record`: its `config.subjects` type and id. */
  readonly subjectType: string | undefined;
  readonly subjectId: string | undefined;
  /** The file format the export asked for; `undefined` uses the export job's. */
  readonly format: DataExportFormat | undefined;
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
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`. Default `better_supabase`.
   */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /** Lifetime of a signed download URL in seconds. Default 300. */
  readonly downloadTtl?: number;
  /** `withBlockHooks` hooks around the methods (ADR 0015). */
  readonly hooks?: NoInfer<BlockHooks<DataLifecycle>>;
  /** Receives the errors `after` hooks throw. */
  readonly logger?: Logger;
}

/** The kind of a data subject request (GDPR Arts. 15 to 20). */
export type DataSubjectRequestKind =
  | "access"
  | "erasure"
  | "rectification"
  | "portability";

/** Where a data subject request stands. */
export type DataSubjectRequestStatus =
  | "received"
  | "verified"
  | "fulfilled"
  | "refused";

const REQUEST_KINDS: readonly DataSubjectRequestKind[] = [
  "access",
  "erasure",
  "rectification",
  "portability",
];

const REQUEST_STATUSES: readonly DataSubjectRequestStatus[] = [
  "received",
  "verified",
  "fulfilled",
  "refused",
];

/** One data subject request with its deadline. */
export interface DataSubjectRequest {
  readonly id: string;
  readonly organizationId: string;
  readonly kind: DataSubjectRequestKind;
  /** Who asked: an email address or a name. */
  readonly requester: string;
  /** The record the request is about, when it names one. */
  readonly subjectType: string | undefined;
  readonly subjectId: string | undefined;
  readonly details: string | undefined;
  readonly status: DataSubjectRequestStatus;
  readonly receivedAt: Temporal.Instant;
  /** 30 days after receipt, or three months after it once extended. */
  readonly dueAt: Temporal.Instant;
  readonly extendedAt: Temporal.Instant | undefined;
  readonly extensionReason: string | undefined;
  readonly verifiedAt: Temporal.Instant | undefined;
  readonly verifiedBy: string | undefined;
  readonly verificationMethod: string | undefined;
  /** The record export an access or portability request started. */
  readonly exportId: string | undefined;
  /** What was done, or why the request was refused. */
  readonly resolution: string | undefined;
  readonly closedAt: Temporal.Instant | undefined;
  /** Only on `dataSubjectRequests()`: open and past its due date. */
  readonly overdue: boolean | undefined;
}

export interface DataLifecycle {
  /**
   * Exports the caller's data, or a tenant's with `organizationId` (needs
   * `data_lifecycle.export`).
   */
  requestExport(options?: {
    readonly organizationId?: string;
  }): AsyncResult<DataExport>;
  /**
   * Exports one `config.subjects` record: its row, with encrypted columns
   * decrypted as the caller (and audited when the table audits reads), and
   * every installed block's rows attached to it. Needs `data_lifecycle.export`
   * in the record's tenant or the record's `manage` action.
   */
  requestSubjectExport(
    subjectType: string,
    subjectId: string,
    options?: { readonly format?: DataExportFormat },
  ): AsyncResult<DataExport>;
  /** The caller's exports, or a tenant's, newest first. */
  exports(organizationId?: string): AsyncResult<readonly DataExport[]>;
  /** Signed URLs for a ready export's files. */
  download(exportId: string): AsyncResult<DataExportDownload>;
  /**
   * Disables the tenant and schedules its purge after `grace` (an interval such
   * as `30 days` or a `Temporal.Duration`; default the module's `grace`
   * option). Needs `organization.delete`.
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
  /**
   * Opens a data subject request with a due date 30 days out. Needs
   * `data_lifecycle.export`. Name the record in `subject` for an access or
   * portability request, which is fulfilled through its record export.
   */
  openDataSubjectRequest(request: {
    readonly organizationId: string;
    readonly kind: DataSubjectRequestKind;
    readonly requester: string;
    readonly subject?: { readonly type: string; readonly id: string };
    readonly details?: string;
  }): AsyncResult<DataSubjectRequest>;
  /** Records how the requester's identity was checked. */
  verifyDataSubjectRequest(
    requestId: string,
    method: string,
  ): AsyncResult<DataSubjectRequest>;
  /** Extends the due date to three months after receipt; once per request. */
  extendDataSubjectRequest(
    requestId: string,
    reason: string,
  ): AsyncResult<DataSubjectRequest>;
  /**
   * Fulfils a verified request. Access and portability start the NDJSON export
   * of the named record. Erasure and rectification need a `resolution`, and an
   * erasure fails while a legal hold covers every kind of record.
   */
  fulfilDataSubjectRequest(
    requestId: string,
    resolution?: string,
  ): AsyncResult<DataSubjectRequest>;
  /** Refuses a request with the reason the requester receives. */
  refuseDataSubjectRequest(
    requestId: string,
    reason: string,
  ): AsyncResult<DataSubjectRequest>;
  /** The organization's requests, the nearest due date first. */
  dataSubjectRequests(
    organizationId: string,
    options?: {
      readonly status?: DataSubjectRequestStatus;
      readonly openOnly?: boolean;
    },
  ): AsyncResult<readonly DataSubjectRequest[]>;
}

const EXPORT_SUBJECTS: readonly DataExport["subject"][] = [
  "user",
  "organization",
  "record",
];

const EXPORT_FORMATS: readonly DataExportFormat[] = ["ndjson", "csv"];

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
    subject:
      EXPORT_SUBJECTS.find((candidate) => candidate === row["subject"]) ??
      "user",
    userId: optionalText(row["user_id"]),
    organizationId: optionalText(row["organization_id"]),
    subjectType: optionalText(row["subject_type"]),
    subjectId: optionalText(row["subject_id"]),
    format: EXPORT_FORMATS.find((candidate) => candidate === row["format"]),
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

function enumOf<T extends string>(
  value: unknown,
  allowed: readonly T[],
  what: string,
): T {
  const found = allowed.find((candidate) => candidate === value);

  if (found === undefined) {
    throw new TypeError(`Unknown ${what} ${JSON.stringify(value)}`);
  }

  return found;
}

function requestOf(value: unknown): DataSubjectRequest {
  const row = recordOf(value, "data_subject_requests");

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organization_id"]),
    kind: enumOf(row["kind"], REQUEST_KINDS, "request kind"),
    requester: textOf(row["requester"]),
    subjectType: optionalText(row["subject_type"]),
    subjectId: optionalText(row["subject_id"]),
    details: optionalText(row["details"]),
    status: enumOf(row["status"], REQUEST_STATUSES, "request status"),
    receivedAt: toInstant(textOf(row["received_at"])),
    dueAt: toInstant(textOf(row["due_at"])),
    extendedAt: optionalInstant(row["extended_at"]),
    extensionReason: optionalText(row["extension_reason"]),
    verifiedAt: optionalInstant(row["verified_at"]),
    verifiedBy: optionalText(row["verified_by"]),
    verificationMethod: optionalText(row["verification_method"]),
    exportId: optionalText(row["export_id"]),
    resolution: optionalText(row["resolution"]),
    closedAt: optionalInstant(row["closed_at"]),
    overdue: typeof row["overdue"] === "boolean" ? row["overdue"] : undefined,
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

/**
 * The table a file holds: `{id}/public.projects.ndjson` gives
 * `public.projects`.
 */
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
    requestSubjectExport: (subjectType, subjectId, request = {}) =>
      call(
        "request_subject_export",
        {
          subject_type: subjectType,
          subject_id: subjectId,
          format: request.format ?? "ndjson",
        },
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

            if (!signed.ok) {
              return signed;
            }

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
    openDataSubjectRequest: (request) =>
      call(
        "open_data_subject_request",
        {
          tenant: request.organizationId,
          kind: request.kind,
          requester: request.requester,
          subject_type: request.subject?.type ?? null,
          subject_id: request.subject?.id ?? null,
          details: request.details ?? null,
        },
        requestOf,
      ),
    verifyDataSubjectRequest: (requestId, method) =>
      call("verify_data_subject_request", { id: requestId, method }, requestOf),
    extendDataSubjectRequest: (requestId, reason) =>
      call("extend_data_subject_request", { id: requestId, reason }, requestOf),
    fulfilDataSubjectRequest: (requestId, resolution) =>
      call(
        "fulfil_data_subject_request",
        { id: requestId, resolution: resolution ?? null },
        requestOf,
      ),
    refuseDataSubjectRequest: (requestId, reason) =>
      call("refuse_data_subject_request", { id: requestId, reason }, requestOf),
    dataSubjectRequests: (organizationId, filter = {}) =>
      call(
        "list_data_subject_requests",
        {
          tenant: organizationId,
          status: filter.status ?? null,
          open_only: filter.openOnly ?? false,
        },
        (value) =>
          recordsOf(value, "list_data_subject_requests").map(requestOf),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "data-lifecycle",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
