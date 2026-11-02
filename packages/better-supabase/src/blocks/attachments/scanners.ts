import type { BlockTransport } from "../../core/block-transport.ts";
import type { DbError } from "../../core/errors.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { EventSink } from "../../events/index.ts";
import type { JobHandler } from "../queue/types.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import type {
  Attachment,
  AttachmentStatus,
  AttachmentStorage,
} from "./attachments.ts";

import { dbError } from "../../core/errors.ts";
import { err, ok } from "../../core/result.ts";
import { eventTypeOf } from "../../events/cloud-event.ts";
import {
  applyTemporal,
  blockCall,
  errorText,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  textOf,
} from "../shared.ts";
import { attachmentOf, lookup, notFound, stored } from "./attachments.ts";

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
  scan(input: {
    id: string;
    signal?: AbortSignal | undefined;
  }): AsyncResult<Attachment>;
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

  const scan = ({
    id,
    signal,
  }: {
    id: string;
    signal?: AbortSignal | undefined;
  }): AsyncResult<Attachment> =>
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
      await settle(scan({ id: payload.attachmentId, signal }), attachmentGone);
    },
    sink: () => ({
      async send(events) {
        for (const event of events) {
          const type = eventTypeOf(event, prefix);

          if (type !== "attachment.uploaded" || !isRecord(event.data)) {
            continue;
          }

          const id = optionalText(event.data["attachmentId"]);

          if (id !== undefined) {
            await settle(scan({ id }), attachmentGone);
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
  scan(input: {
    bucket: string;
    path: string;
    signal?: AbortSignal | undefined;
  }): AsyncResult<ScannedObject>;
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

  const scan = ({
    bucket,
    path,
    signal,
  }: {
    bucket: string;
    path: string;
    signal?: AbortSignal | undefined;
  }): AsyncResult<ScannedObject> =>
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
      await settle(
        scan({ bucket: payload.bucket, path: payload.path, signal }),
        objectGone,
      );
    },
    sink: () => ({
      async send(events) {
        for (const event of events) {
          const type = eventTypeOf(event, prefix);

          if (type !== "object.uploaded" || !isRecord(event.data)) {
            continue;
          }

          const bucket = optionalText(event.data["bucket"]);
          const path = optionalText(event.data["path"]);

          if (bucket !== undefined && path !== undefined) {
            await settle(scan({ bucket, path }), objectGone);
          }
        }
      },
    }),
  };
}
