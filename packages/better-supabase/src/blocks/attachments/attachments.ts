import type { BlockTransport } from "../../core/block-transport.ts";
import type { DbError, ErrorMapper } from "../../core/errors.ts";
import type { EventSink } from "../../events/index.ts";
import type { JobHandler } from "../jobs/queue.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { fromStorageError } from "../../storage/errors.ts";
import {
  blockCall,
  errorText,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
  toInstant,
  type BlockTemporalOptions,
  applyTemporal,
} from "../shared.ts";

interface StorageReply<T> {
  readonly data: T | null;
  readonly error: unknown;
}

/** The `supabase.storage.from(bucket)` methods attachments use. */
export interface AttachmentBucket {
  createSignedUploadUrl(
    path: string,
  ): PromiseLike<
    StorageReply<{ readonly signedUrl: string; readonly token: string }>
  >;
  createSignedUrl(
    path: string,
    expiresIn: number,
    options?: { download?: string | boolean },
  ): PromiseLike<StorageReply<{ readonly signedUrl: string }>>;
  download(path: string): PromiseLike<StorageReply<Blob>>;
  remove(paths: string[]): PromiseLike<StorageReply<unknown>>;
}

/** `supabase.storage`, typed structurally. */
export interface AttachmentStorage {
  from(bucket: string): AttachmentBucket;
}

export interface AttachmentsOptions extends BlockTemporalOptions {
  /** The caller's transport (`rpcTransport(supabase)`). */
  readonly transport: BlockTransport;
  /** The caller's `supabase.storage`, so the bucket policies apply. */
  readonly storage: AttachmentStorage;
  /** The module schema (`sql.modules.attachments.schema`), default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /** Must match `sql.modules.attachments.options.requireScan`. Default `true`. */
  readonly requireScan?: boolean;
  /** Lifetime of a signed download URL in seconds. Default 300. */
  readonly downloadTtl?: number;
}

export type AttachmentStatus = "pending" | "clean" | "infected" | "failed";

export interface Attachment {
  readonly id: string;
  readonly organizationId: string;
  readonly subjectType: string | undefined;
  readonly subjectId: string | undefined;
  readonly bucket: string;
  /** The object path in the bucket, `{organizationId}/attachments/{id}` unless `options.path` says otherwise. */
  readonly path: string;
  readonly name: string;
  readonly mimeType: string;
  readonly size: number;
  readonly status: AttachmentStatus;
  /** What the scanner reported, such as the signature it matched. */
  readonly scanDetail: string | undefined;
  /** What `upload` stored with the file; `{}` without any. */
  readonly metadata: Readonly<Record<string, unknown>>;
  readonly uploadedBy: string | undefined;
  readonly createdAt: Temporal.Instant;
  /** Set by `confirm()` once the object exists. */
  readonly uploadedAt: Temporal.Instant | undefined;
  readonly scannedAt: Temporal.Instant | undefined;
}

export interface NewAttachment {
  readonly organizationId: string;
  readonly name: string;
  readonly mimeType: string;
  /** Bytes; `confirm()` replaces it with the stored size. */
  readonly size: number;
  readonly subjectType?: string;
  readonly subjectId?: string;
  /** App data about the file, such as a caption or its source, kept with the record. */
  readonly metadata?: Readonly<Record<string, unknown>>;
}

export interface AttachmentUpload {
  readonly attachment: Attachment;
  /** PUT the file here, or pass `token` to `uploadToSignedUrl(path, token, file)`. */
  readonly signedUrl: string;
  readonly token: string;
}

export interface AttachmentDownload {
  readonly attachment: Attachment;
  readonly signedUrl: string;
}

export interface Attachments {
  /** Creates the pending record and a signed upload URL for its path. */
  upload(attachment: NewAttachment): AsyncResult<AttachmentUpload>;
  /** Marks the upload done after the file is stored; emits `attachment.uploaded`. */
  confirm(id: string): AsyncResult<Attachment>;
  get(id: string): AsyncResult<Attachment>;
  list(
    organizationId: string,
    subject?: { readonly type: string; readonly id: string },
  ): AsyncResult<readonly Attachment[]>;
  /**
   * A signed URL for a file the scanner passed. `invalid_request` with hint
   * `ATTACHMENT_NOT_SCANNED` until then, and for an infected file.
   */
  download(
    id: string,
    options?: { readonly as?: string | boolean },
  ): AsyncResult<AttachmentDownload>;
  /** Deletes the file, then the record (the uploader, or `attachments.manage`). */
  remove(id: string): AsyncResult<boolean>;
}

const STATUSES: readonly AttachmentStatus[] = [
  "pending",
  "clean",
  "infected",
  "failed",
];

function statusOf(value: unknown): AttachmentStatus {
  const status = STATUSES.find((candidate) => candidate === value);
  if (status === undefined) {
    throw new TypeError(`Unknown attachment status ${JSON.stringify(value)}`);
  }
  return status;
}

function attachmentOf(value: unknown): Attachment {
  const row = recordOf(value, "attachments");
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organization_id"]),
    subjectType: optionalText(row["subject_type"]),
    subjectId: optionalText(row["subject_id"]),
    bucket: textOf(row["bucket"]),
    path: textOf(row["object_path"]),
    name: textOf(row["name"]),
    mimeType: textOf(row["mime_type"]),
    size: Number(row["size"]),
    status: statusOf(row["status"]),
    scanDetail: optionalText(row["scan_detail"]),
    metadata: isRecord(row["metadata"]) ? row["metadata"] : {},
    uploadedBy: optionalText(row["uploaded_by"]),
    createdAt: toInstant(textOf(row["created_at"])),
    uploadedAt: optionalInstant(row["uploaded_at"]),
    scannedAt: optionalInstant(row["scanned_at"]),
  };
}

const notFound = (): DbError =>
  dbError("not_found", "No attachment you can see has this id", {
    hint: "ATTACHMENT_NOT_FOUND",
  });

function stored<T>(
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

function lookup(
  call: ReturnType<typeof blockCall>,
  id: string,
): AsyncResult<Attachment> {
  return call("get_attachment", { id }, (value) => value).andThen((value) =>
    Promise.resolve(
      isRecord(value) ? ok(attachmentOf(value)) : err(notFound()),
    ),
  );
}

/** Attachments as the caller: the table's and the bucket's policies apply. */
export function createAttachments(options: AttachmentsOptions): Attachments {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const requireScan = options.requireScan ?? true;
  const ttl = options.downloadTtl ?? 300;
  const bucket = (attachment: Attachment): AttachmentBucket =>
    options.storage.from(attachment.bucket);
  return {
    upload: (attachment) =>
      call(
        "create_attachment",
        {
          tenant: attachment.organizationId,
          name: attachment.name,
          mime_type: attachment.mimeType,
          size: attachment.size,
          subject_type: attachment.subjectType,
          subject_id: attachment.subjectId,
          metadata: attachment.metadata,
        },
        attachmentOf,
      ).andThen((created) =>
        stored(bucket(created).createSignedUploadUrl(created.path)).map(
          (url) => ({
            attachment: created,
            signedUrl: url.signedUrl,
            token: url.token,
          }),
        ),
      ),
    confirm: (id) => call("confirm_attachment", { id }, attachmentOf),
    get: (id) => lookup(call, id),
    list: (organizationId, subject) =>
      call(
        "list_attachments",
        {
          tenant: organizationId,
          subject_type: subject?.type,
          subject_id: subject?.id,
        },
        (value) => recordsOf(value, "list_attachments").map(attachmentOf),
      ),
    download: (id, download = {}) =>
      lookup(call, id).andThen((attachment) => {
        const readable =
          attachment.status === "clean" ||
          (!requireScan &&
            attachment.status !== "infected" &&
            attachment.uploadedAt !== undefined);
        if (!readable) {
          return Promise.resolve(
            err(
              dbError(
                "invalid_request",
                attachment.status === "infected"
                  ? "The file failed the malware scan"
                  : "The file is not scanned yet",
                { hint: "ATTACHMENT_NOT_SCANNED" },
              ),
            ),
          );
        }
        return stored(
          bucket(attachment).createSignedUrl(
            attachment.path,
            ttl,
            download.as === undefined ? undefined : { download: download.as },
          ),
        ).map((url) => ({ attachment, signedUrl: url.signedUrl }));
      }),
    remove: (id) =>
      lookup(call, id)
        .andThen((attachment) =>
          stored(bucket(attachment).remove([attachment.path])),
        )
        .andThen(() =>
          call("delete_attachment", { id }, (value) => value === true),
        ),
  };
}

/** A scanner's verdict on one file. */
export interface ScanVerdict {
  readonly status: "clean" | "infected";
  /** Stored as `scan_detail`, such as the matched signature. */
  readonly detail?: string;
}

export interface AttachmentScannerOptions extends BlockTemporalOptions {
  /** A service-role transport: `set_attachment_status()` is granted to `service_role` only. */
  readonly transport: BlockTransport;
  /** A service-role `supabase.storage`, to read pending files. */
  readonly storage: AttachmentStorage;
  readonly schema?: string;
  /** Scans the file (ClamAV, a scanning API). A throw records `failed` and rethrows. */
  readonly scan: (
    file: Blob,
    attachment: Attachment,
    signal?: AbortSignal,
  ) => ScanVerdict | Promise<ScanVerdict>;
  /** The outbox `typePrefix`. Default `dev.better-supabase`. */
  readonly typePrefix?: string;
}

/** The payload `job` expects. */
export interface AttachmentScanJob {
  readonly attachmentId: string;
}

export interface AttachmentScanner {
  /** Scans one uploaded file and records the verdict. */
  scan(id: string, signal?: AbortSignal): AsyncResult<Attachment>;
  /** A jobs handler: `queue.work('attachment-scans', scanner.job)`. */
  readonly job: JobHandler<AttachmentScanJob>;
  /** An outbox sink that scans each `attachment.uploaded` event's file. */
  sink(): EventSink;
}

/**
 * Scans uploaded files with the app's `scan` function and records `clean`,
 * `infected` or `failed`. A file already clean or infected is not scanned
 * again, so replayed events and retried jobs are safe.
 */
export function createAttachmentScanner(
  options: AttachmentScannerOptions,
): AttachmentScanner {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema);
  const prefix = `${options.typePrefix ?? "dev.better-supabase"}.`;
  const record = (
    id: string,
    status: "clean" | "infected" | "failed",
    detail: string | undefined,
  ): AsyncResult<Attachment> =>
    call(
      "set_attachment_status",
      { id, status, detail },
      (value) => value,
    ).andThen((value) =>
      Promise.resolve(
        isRecord(value) ? ok(attachmentOf(value)) : err(notFound()),
      ),
    );
  const scan = (id: string, signal?: AbortSignal): AsyncResult<Attachment> =>
    lookup(call, id).andThen((attachment) => {
      if (attachment.status === "clean" || attachment.status === "infected") {
        return Promise.resolve(ok(attachment));
      }
      if (attachment.uploadedAt === undefined) {
        return Promise.resolve(
          err(
            dbError("invalid_request", "The file was not uploaded yet", {
              hint: "ATTACHMENT_NOT_UPLOADED",
            }),
          ),
        );
      }
      return stored(
        options.storage.from(attachment.bucket).download(attachment.path),
      ).andThen(async (file) => {
        let verdict: ScanVerdict;
        try {
          verdict = await options.scan(file, attachment, signal);
        } catch (cause) {
          const failed = await record(id, "failed", errorText(cause));
          return failed.ok
            ? err(
                dbError("raised", `The scan failed: ${errorText(cause)}`, {
                  hint: "ATTACHMENT_SCAN_FAILED",
                }),
              )
            : failed;
        }
        return record(id, verdict.status, verdict.detail);
      });
    });
  return {
    scan,
    job: async (payload, _job, signal) => {
      await scan(payload.attachmentId, signal).orThrow();
    },
    sink: () => ({
      async send(events) {
        for (const event of events) {
          const type = event.type.startsWith(prefix)
            ? event.type.slice(prefix.length)
            : event.type;
          if (type !== "attachment.uploaded" || !isRecord(event.data)) continue;
          const id = optionalText(event.data["attachmentId"]);
          if (id !== undefined) await scan(id).orThrow();
        }
      },
    }),
  };
}

/** A scanned object in any bucket (`scanned_objects`). */
export interface ScannedObject {
  readonly bucket: string;
  readonly path: string;
  readonly status: AttachmentStatus;
  readonly detail: string | undefined;
  readonly scannedAt: Temporal.Instant | undefined;
}

export interface ObjectScannerOptions extends BlockTemporalOptions {
  /** A service-role transport: `set_object_scan()` is granted to `service_role` only. */
  readonly transport: BlockTransport;
  /** A service-role `supabase.storage`, to read the objects. */
  readonly storage: AttachmentStorage;
  readonly schema?: string;
  /** Scans the file. A throw records `failed` and rethrows. */
  readonly scan: (
    file: Blob,
    object: { readonly bucket: string; readonly path: string },
    signal?: AbortSignal,
  ) => ScanVerdict | Promise<ScanVerdict>;
  /** The outbox `typePrefix`. Default `dev.better-supabase`. */
  readonly typePrefix?: string;
}

/** The payload `ObjectScanner.job` expects. */
export interface ObjectScanJob {
  readonly bucket: string;
  readonly path: string;
}

export interface ObjectScanner {
  /** Scans one object and records the verdict; a clean or infected object is not scanned again. */
  scan(
    bucket: string,
    path: string,
    signal?: AbortSignal,
  ): AsyncResult<ScannedObject>;
  /** A jobs handler: `queue.work('object-scans', scanner.job)`. */
  readonly job: JobHandler<ObjectScanJob>;
  /** An outbox sink that scans each `object.uploaded` event's object. */
  sink(): EventSink;
}

function scannedOf(value: unknown): ScannedObject {
  const row = recordOf(value, "scanned_objects");
  const status = textOf(row["status"]);
  return {
    bucket: textOf(row["bucket"]),
    path: textOf(row["object_path"]),
    status:
      status === "clean" || status === "infected" || status === "failed"
        ? status
        : "pending",
    detail: optionalText(row["scan_detail"]),
    scannedAt: optionalInstant(row["scanned_at"]),
  };
}

/**
 * The scan gate for objects outside the attachments table, such as a file
 * drive or avatars: scans an object with the app's `scan` function and
 * records the verdict in `scanned_objects`, which storage policies read with
 * `object_clean(bucket_id, name)`. With `options.scanBuckets`, new objects in
 * those buckets get a pending row and an `object.uploaded` event.
 */
export function createObjectScanner(
  options: ObjectScannerOptions,
): ObjectScanner {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema);
  const prefix = `${options.typePrefix ?? "dev.better-supabase"}.`;
  const record = (
    bucket: string,
    path: string,
    status: AttachmentStatus,
    detail: string | undefined,
  ): AsyncResult<ScannedObject> =>
    call("set_object_scan", { bucket, path, status, detail }, scannedOf);
  const scan = (
    bucket: string,
    path: string,
    signal?: AbortSignal,
  ): AsyncResult<ScannedObject> =>
    call("object_scan", { bucket, path }, (value) =>
      isRecord(value) ? scannedOf(value) : undefined,
    ).andThen((current) => {
      if (current?.status === "clean" || current?.status === "infected") {
        return Promise.resolve(ok(current));
      }
      return stored(options.storage.from(bucket).download(path)).andThen(
        async (file) => {
          let verdict: ScanVerdict;
          try {
            verdict = await options.scan(file, { bucket, path }, signal);
          } catch (cause) {
            const failed = await record(
              bucket,
              path,
              "failed",
              errorText(cause),
            );
            return failed.ok
              ? err(
                  dbError("raised", `The scan failed: ${errorText(cause)}`, {
                    hint: "ATTACHMENT_SCAN_FAILED",
                  }),
                )
              : failed;
          }
          return record(bucket, path, verdict.status, verdict.detail);
        },
      );
    });
  return {
    scan,
    job: async (payload, _job, signal) => {
      await scan(payload.bucket, payload.path, signal).orThrow();
    },
    sink: () => ({
      async send(events) {
        for (const event of events) {
          const type = event.type.startsWith(prefix)
            ? event.type.slice(prefix.length)
            : event.type;
          if (type !== "object.uploaded" || !isRecord(event.data)) continue;
          const bucket = optionalText(event.data["bucket"]);
          const path = optionalText(event.data["path"]);
          if (bucket !== undefined && path !== undefined)
            await scan(bucket, path).orThrow();
        }
      },
    }),
  };
}
