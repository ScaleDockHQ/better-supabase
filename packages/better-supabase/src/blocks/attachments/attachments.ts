import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { DbError, ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { EventSink } from "../../events/index.ts";
import type { JobHandler } from "../jobs/types.ts";

import {
  allWithFields,
  type BlockFields,
  blockFields,
  extraOf,
  extraFieldsArg,
  type FieldsOf,
  withFields,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok, type Result } from "../../core/result.ts";
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
import {
  claimsUploads,
  claimUpload,
  type UploadClaimStorage,
} from "../upload-claim.ts";

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
  /** Used by `put`, which uploads from the server. */
  upload?(
    path: string,
    body: Blob | ArrayBuffer | Uint8Array,
    options?: { readonly contentType?: string; readonly upsert?: boolean },
  ): PromiseLike<StorageReply<unknown>>;
}

/** `supabase.storage`, typed structurally. */
export interface AttachmentStorage extends UploadClaimStorage {
  from(bucket: string): AttachmentBucket;
}

export interface AttachmentsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  /**
   * A Standard Schema for the attachment columns the app adds
   * (`blocks.attachments.options.extraColumns`), keyed by column name. It types
   * and parses them on every read, and validates them on `upload` and `put`,
   * which return a `validation` error for a bad value.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Attachments<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  /** The caller's transport (`rpcTransport(supabase)`). */
  readonly transport: BlockTransport;
  /** The caller's `supabase.storage`, so the bucket policies apply. */
  readonly storage: AttachmentStorage;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`. Default `better_supabase`.
   */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /**
   * `blocks.attachments.options.requireScan`, which `defineBlocks` passes from
   * `blocks.generated.ts`. Default `true`.
   */
  readonly requireScan?: boolean;
  /** Lifetime of a signed download URL in seconds. Default 300. */
  readonly downloadTtl?: number;
}

export type AttachmentStatus = "pending" | "clean" | "infected" | "failed";

export interface Attachment {
  readonly id: string;
  /** `undefined` for a file of a subject without a tenant (`tenant: false`). */
  readonly organizationId: string | undefined;
  readonly subjectType: string | undefined;
  readonly subjectId: string | undefined;
  readonly bucket: string;
  /**
   * The object path in the bucket, `{organizationId}/attachments/{id}` unless
   * `options.path` says otherwise.
   */
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
  /** `null` for a subject type configured with `tenant: false`. */
  readonly organizationId: string | null;
  readonly name: string;
  readonly mimeType: string;
  /** Bytes; `confirm()` replaces it with the stored size. */
  readonly size: number;
  readonly subjectType?: string;
  readonly subjectId?: string;
  /**
   * App data about the file, such as a caption or its source, kept with the
   * record.
   */
  readonly metadata?: Readonly<Record<string, unknown>>;
}

export interface AttachmentUpload<F extends object = Record<never, never>> {
  readonly attachment: Attachment & F;
  /**
   * PUT the file here, or pass `token` to `uploadToSignedUrl(path, token,
   * file)`.
   */
  readonly signedUrl: string;
  readonly token: string;
}

export interface AttachmentDownload<F extends object = Record<never, never>> {
  readonly attachment: Attachment & F;
  readonly signedUrl: string;
}

/** `F` is the extra attachment fields `options.fields` describes. */
export interface Attachments<F extends object = Record<never, never>> {
  /**
   * Creates the pending record and a signed upload URL for its path. When
   * Storage refuses the URL, the record is deleted again.
   */
  upload(
    attachment: NewAttachment & Partial<F>,
  ): AsyncResult<AttachmentUpload<F>>;
  /**
   * Marks the upload done after the file is stored; emits
   * `attachment.uploaded`.
   */
  confirm(id: string): AsyncResult<Attachment & F>;
  get(id: string): AsyncResult<Attachment & F>;
  list(
    organizationId: string | null,
    subject?: { readonly type: string; readonly id: string },
  ): AsyncResult<readonly (Attachment & F)[]>;
  /**
   * A signed URL for a file the scanner passed. `invalid_request` with hint
   * `ATTACHMENT_NOT_SCANNED` until then, and for an infected file.
   */
  download(
    id: string,
    options?: { readonly as?: string | boolean },
  ): AsyncResult<AttachmentDownload<F>>;
  /** Deletes the file, then the record (the uploader, or `attachments.manage`). */
  remove(id: string): AsyncResult<boolean>;
  /**
   * Creates the record, uploads `file` from the server and confirms it, for
   * files the server makes or fetches (an export, a generated PDF, an import).
   * Returns the confirmed attachment, which still waits for the scan when the
   * module requires one. When Storage refuses the upload, the record is deleted
   * again, so no pending record is left behind.
   */
  put(
    attachment: NewAttachment & Partial<F>,
    file: Blob | ArrayBuffer | Uint8Array,
  ): AsyncResult<Attachment & F>;
  /**
   * The file's bytes, for server-side processing, behind the same scan gate as
   * `download`: `ATTACHMENT_NOT_SCANNED` until the scan passes.
   */
  read(
    id: string,
  ): AsyncResult<{ readonly attachment: Attachment & F; readonly file: Blob }>;
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

/** An attachments row, as `get_attachment` and `create_attachment` return it. */
export function attachmentOf(value: unknown): Attachment {
  const row = recordOf(value, "attachments");

  return {
    id: textOf(row["id"]),
    organizationId: optionalText(row["organization_id"]),
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

const CLAIM_HINTS = {
  notUploaded: "ATTACHMENT_NOT_UPLOADED",
  forbidden: "ATTACHMENT_FORBIDDEN",
} as const;

const notFound = (): DbError =>
  dbError("not_found", "No attachment you can see has this id", {
    hint: "ATTACHMENT_NOT_FOUND",
  });

/** A Storage reply as a result, its error mapped to a `DbError`. */
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
 * Waits for a scan from a job or an event. A scan whose target is gone (the
 * attachment row, or for an object the stored object) is done, not a failure,
 * so the job or event is not retried; every other error throws.
 */
async function settle(
  scanned: AsyncResult<unknown>,
  gone: (error: DbError) => boolean,
): Promise<void> {
  const result = await scanned;

  if (result.ok || gone(result.error)) {
    return;
  }

  await scanned.orThrow();
}

const attachmentGone = (error: DbError): boolean =>
  error.kind === "not_found" && error.hint === "ATTACHMENT_NOT_FOUND";

const objectGone = (error: DbError): boolean =>
  error.kind === "not_found" && error.code === "NoSuchKey";

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
const NEW_ATTACHMENT: ReadonlySet<string> = new Set([
  "organizationId",
  "name",
  "mimeType",
  "size",
  "subjectType",
  "subjectId",
  "metadata",
]);

export function createAttachments<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: AttachmentsOptions<S>): Attachments<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const fields: BlockFields<F> = blockFields(
    options.fields,
    "attachment fields",
  );

  const typed = (value: unknown): AsyncResult<Attachment & F> =>
    AsyncResult.from(() => withFields(fields, value, attachmentOf(value)));

  const find = (id: string): AsyncResult<Attachment & F> =>
    call("get_attachment", { id }, (value) => value).andThen((value) =>
      isRecord(value) ? typed(value) : AsyncResult.err(notFound()),
    );

  const confirmed = (id: string): AsyncResult<Attachment & F> =>
    call("confirm_attachment", { id }, (value) => value).andThen(typed);

  const confirm = (id: string): AsyncResult<Attachment & F> =>
    claimsUploads(options.storage)
      ? lookup(call, id).andThen((attachment) =>
          attachment.uploadedAt === undefined
            ? claimUpload(options.storage, attachment, CLAIM_HINTS).andThen(
                () => confirmed(id),
              )
            : confirmed(id),
        )
      : confirmed(id);

  const requireScan = options.requireScan ?? true;
  const ttl = options.downloadTtl ?? 300;

  const bucket = (attachment: Attachment): AttachmentBucket =>
    options.storage.from(attachment.bucket);

  /** Why a file can't be read yet, or `undefined` once it can. */
  const gate = (attachment: Attachment): DbError | undefined => {
    const readable =
      attachment.status === "clean" ||
      (!requireScan &&
        attachment.status !== "infected" &&
        attachment.uploadedAt !== undefined);

    return readable
      ? undefined
      : dbError(
          "invalid_request",
          attachment.status === "infected"
            ? "The file failed the malware scan"
            : "The file is not scanned yet",
          { hint: "ATTACHMENT_NOT_SCANNED" },
        );
  };

  const discard = async (
    created: Attachment,
    error: DbError,
  ): Promise<Result<never>> => {
    await call("delete_attachment", { id: created.id }, (value) => value);

    return err(error);
  };

  const create = (attachment: NewAttachment): AsyncResult<Attachment & F> =>
    AsyncResult.from(() =>
      extraFieldsArg(fields, extraOf(attachment, NEW_ATTACHMENT)),
    )
      .andThen((more) =>
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
            ...more,
          },
          (value) => value,
        ),
      )
      .andThen(typed);

  const upload = (
    attachment: NewAttachment,
  ): AsyncResult<AttachmentUpload<F>> =>
    create(attachment).andThen(async (created) => {
      const url = await stored(
        bucket(created).createSignedUploadUrl(created.path),
      );

      if (!url.ok) {
        return discard(created, url.error);
      }

      return ok({
        attachment: created,
        signedUrl: url.data.signedUrl,
        token: url.data.token,
      });
    });

  const client: Attachments<F> = {
    upload,
    confirm,
    get: find,
    list: (organizationId, subject) =>
      call(
        "list_attachments",
        {
          tenant: organizationId,
          subject_type: subject?.type,
          subject_id: subject?.id,
        },
        (value) =>
          recordsOf(value, "list_attachments").map(
            (raw) => [raw, attachmentOf(raw)] as const,
          ),
      ).andThen((rows) => allWithFields(fields, rows)),
    download: (id, download = {}) =>
      find(id).andThen((attachment) => {
        const blocked = gate(attachment);

        if (blocked) {
          return Promise.resolve(err(blocked));
        }

        return stored(
          bucket(attachment).createSignedUrl(
            attachment.path,
            ttl,
            download.as === undefined ? undefined : { download: download.as },
          ),
        ).map((url) => ({ attachment, signedUrl: url.signedUrl }));
      }),
    put: (attachment, file) =>
      create(attachment).andThen(async (created) => {
        const target = bucket(created);

        if (!target.upload) {
          return discard(
            created,
            dbError("invalid_request", "The storage client has no upload", {
              hint: "ATTACHMENT_STORAGE_CLIENT",
            }),
          );
        }

        const sent = await stored(
          target.upload(created.path, file, {
            contentType: created.mimeType,
            upsert: false,
          }),
        );

        if (!sent.ok) {
          return discard(created, sent.error);
        }

        return confirmed(created.id);
      }),
    read: (id) =>
      find(id).andThen((attachment) => {
        const blocked = gate(attachment);

        if (blocked) {
          return Promise.resolve(err(blocked));
        }

        return stored(bucket(attachment).download(attachment.path)).map(
          (file) => ({ attachment, file }),
        );
      }),
    remove: (id) =>
      find(id)
        .andThen((attachment) =>
          stored(bucket(attachment).remove([attachment.path])),
        )
        .andThen(() =>
          call("delete_attachment", { id }, (value) => value === true),
        ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "attachments",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}

/** A scanner's verdict on one file. */
export interface ScanVerdict {
  readonly status: "clean" | "infected";
  /** Stored as `scan_detail`, such as the matched signature. */
  readonly detail?: string;
}

export interface AttachmentScannerOptions extends BlockTemporalOptions {
  /**
   * A service-role transport: `set_attachment_status()` is granted to
   * `service_role` only.
   */
  readonly transport: BlockTransport;
  /** A service-role `supabase.storage`, to read pending files. */
  readonly storage: AttachmentStorage;
  readonly schema?: string;
  /**
   * Scans the file (ClamAV, a scanning API). A throw records `failed` and
   * rethrows.
   */
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
  /**
   * A jobs handler: `queue.work('attachment-scans', scanner.job)`. A deleted
   * attachment completes the job; other errors throw so the queue retries.
   */
  readonly job: JobHandler<AttachmentScanJob>;
  /**
   * An outbox sink that scans each `attachment.uploaded` event's file. An event
   * for a deleted attachment is skipped, so it never holds up the events behind
   * it; other errors throw so the relay retries the batch.
   */
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
      await settle(scan(payload.attachmentId, signal), attachmentGone);
    },
    sink: () => ({
      async send(events) {
        for (const event of events) {
          const type = event.type.startsWith(prefix)
            ? event.type.slice(prefix.length)
            : event.type;

          if (type !== "attachment.uploaded" || !isRecord(event.data)) {
            continue;
          }

          const id = optionalText(event.data["attachmentId"]);

          if (id !== undefined) {
            await settle(scan(id), attachmentGone);
          }
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
  /**
   * A service-role transport: `set_object_scan()` is granted to `service_role`
   * only.
   */
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
  /**
   * Scans one object and records the verdict; a clean or infected object is not
   * scanned again.
   */
  scan(
    bucket: string,
    path: string,
    signal?: AbortSignal,
  ): AsyncResult<ScannedObject>;
  /**
   * A jobs handler: `queue.work('object-scans', scanner.job)`. An object
   * deleted from storage completes the job; other errors throw.
   */
  readonly job: JobHandler<ObjectScanJob>;
  /**
   * An outbox sink that scans each `object.uploaded` event's object. An event
   * for an object deleted from storage is skipped; other errors throw so the
   * relay retries the batch.
   */
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
 * The scan gate for objects outside the attachments table, such as a file drive
 * or avatars: scans an object with the app's `scan` function and records the
 * verdict in `scanned_objects`, which storage policies read with
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
      await settle(scan(payload.bucket, payload.path, signal), objectGone);
    },
    sink: () => ({
      async send(events) {
        for (const event of events) {
          const type = event.type.startsWith(prefix)
            ? event.type.slice(prefix.length)
            : event.type;

          if (type !== "object.uploaded" || !isRecord(event.data)) {
            continue;
          }

          const bucket = optionalText(event.data["bucket"]);
          const path = optionalText(event.data["path"]);

          if (bucket !== undefined && path !== undefined) {
            await settle(scan(bucket, path), objectGone);
          }
        }
      },
    }),
  };
}
