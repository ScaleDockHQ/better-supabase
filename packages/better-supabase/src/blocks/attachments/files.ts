import type { BlockCall } from "../../core/block-helpers.ts";
import type { DbError } from "../../core/errors.ts";
import type {
  FileStore,
  SignedUpload,
  SupabaseFileStorage,
} from "../../storage/file-store.ts";
import type { Attachment } from "./attachments.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import {
  fileStoreOf,
  isSupabaseFileStore,
  supabaseFileStore,
} from "../../storage/file-store.ts";

/**
 * The store a block keeps bytes in: `files`, else Supabase Storage from
 * `storage`.
 */
export function blockFiles(options: {
  readonly files?: FileStore | undefined;
  readonly storage?: SupabaseFileStorage | undefined;
}): FileStore | undefined {
  if (options.files !== undefined) {
    return fileStoreOf(options.files);
  }

  return options.storage === undefined
    ? undefined
    : supabaseFileStore(options.storage);
}

/** `blockFiles` for a service that can't run without a store. */
export function requiredFiles(
  creator: string,
  options: {
    readonly files?: FileStore | undefined;
    readonly storage?: SupabaseFileStorage | undefined;
  },
): FileStore {
  const files = blockFiles(options);

  if (files === undefined) {
    throw new TypeError(`${creator} needs storage or files`);
  }

  return files;
}

/** The Supabase Storage behind `files`, for what only Supabase has. */
export const supabaseOf = (
  files: FileStore | undefined,
): SupabaseFileStorage | undefined =>
  files !== undefined && isSupabaseFileStore(files) ? files.storage : undefined;

/** Puts the block's hint on a store error for a client that lacks a method. */
export const hinted =
  (hint: string) =>
  (error: DbError): DbError =>
    error.hint === "STORAGE_CLIENT" ? { ...error, hint } : error;

/** A feature the store can't serve: image transforms, public URLs. */
export const unsupported = (files: FileStore, what: string): DbError =>
  dbError(
    "invalid_request",
    `${what} need Supabase Storage; the file store "${files.name}" has none`,
    { hint: "ATTACHMENT_STORE_UNSUPPORTED" },
  );

/**
 * Where a browser sends the bytes of `file`, limited to its declared type and
 * size where the store can.
 */
export function signUpload(
  files: FileStore,
  file: Pick<Attachment, "bucket" | "path" | "mimeType" | "size">,
  hint: string,
): AsyncResult<SignedUpload> {
  if (!files.signedUploadUrl) {
    return AsyncResult.err(
      dbError(
        "invalid_request",
        `The file store "${files.name}" has no signedUploadUrl`,
        { hint },
      ),
    );
  }

  return files
    .signedUploadUrl(file.bucket, file.path, {
      contentType: file.mimeType,
      maxSize: file.size,
    })
    .mapError(hinted(hint));
}

/**
 * What an upload result carries: `signedUrl` and `token`, plus `method` and
 * `headers` for a store other than Supabase.
 */
export interface UploadTicket {
  readonly signedUrl: string;
  /** Supabase's upload token; empty for a store without one. */
  readonly token: string;
  /** How to send the bytes; set for a store other than Supabase. */
  readonly method?: "PUT" | "POST";
  /** The headers to send with the bytes; set for a store other than Supabase. */
  readonly headers?: Readonly<Record<string, string>>;
}

/** The `UploadTicket` for a store's signed upload. */
export function uploadTicket(
  files: FileStore,
  upload: SignedUpload,
): UploadTicket {
  const ticket = { signedUrl: upload.url, token: upload.token ?? "" };

  return isSupabaseFileStore(files)
    ? ticket
    : { ...ticket, method: upload.method, headers: upload.headers };
}

/** Sends `body` to a store's signed upload URL with `fetch`. */
export function sendToSignedUrl(
  ticket: UploadTicket,
  body: Blob,
): AsyncResult<null> {
  return AsyncResult.from(async () => {
    let response: Response;

    try {
      response = await fetch(ticket.signedUrl, {
        method: ticket.method ?? "PUT",
        headers: {
          ...(body.type === "" ? {} : { "content-type": body.type }),
          ...ticket.headers,
        },
        body,
      });
    } catch {
      return err(
        dbError("network", "The upload did not reach the file store", {
          hint: "ATTACHMENT_UPLOAD_FAILED",
        }),
      );
    }

    return response.ok
      ? ok(null)
      : err(
          dbError(
            "network",
            `The file store refused the upload (${String(response.status)})`,
            { hint: "ATTACHMENT_UPLOAD_FAILED" },
          ),
        );
  });
}

/** Whether `error` says the object isn't in `storage.objects` yet. */
export const notUploaded = (error: DbError): boolean =>
  error.hint === "ATTACHMENT_NOT_UPLOADED";

/**
 * Confirms an upload to a store Postgres can't see: reads the file's size and
 * type from the store with `head`, never from the browser, and passes them to
 * `confirm_attachment` as the service role, the only caller it takes them from.
 * The caller checks first that its own `confirm_attachment` call failed only
 * because Storage has no object, so the uploader rule still applies.
 */
export function confirmInStore(
  files: FileStore,
  service: BlockCall,
  file: Pick<Attachment, "id" | "bucket" | "path">,
  hint: string,
): AsyncResult<unknown> {
  return AsyncResult.from(async () => {
    if (!files.head) {
      return err(
        dbError(
          "invalid_request",
          `The file store "${files.name}" has no head, so uploads can't be confirmed`,
          { hint },
        ),
      );
    }

    const head = await files
      .head(file.bucket, file.path)
      .mapError(hinted(hint));

    if (!head.ok) {
      return head;
    }

    if (head.data === undefined) {
      return err(
        dbError("not_found", "The file was not uploaded yet", {
          hint: "ATTACHMENT_NOT_UPLOADED",
        }),
      );
    }

    const confirmed = await service(
      "confirm_attachment",
      {
        id: file.id,
        object: { size: head.data.size, mimetype: head.data.contentType },
      },
      (raw) => raw,
    );

    return !confirmed.ok && notUploaded(confirmed.error)
      ? err(
          dbError(
            "invalid_request",
            "Confirming a file in another store needs a service-role transport: pass service",
            { hint: "ATTACHMENT_SERVICE_REQUIRED" },
          ),
        )
      : confirmed;
  });
}
