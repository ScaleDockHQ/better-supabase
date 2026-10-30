import type {
  Attachment,
  AttachmentStorage,
} from "../attachments/attachments.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult } from "../../core/result.ts";
import { stored } from "../attachments/attachments.ts";

/**
 * A file from a caller who may only add files to the folder: PUT the bytes to
 * `signedUrl`, then call `commitContribution`. It carries the new file's id and
 * no node, because the caller can't read it.
 */
export interface DriveContribution {
  readonly id: string;
  readonly attachment: Attachment;
  readonly signedUrl: string;
  readonly token: string;
}

/** A file request: an upload share link on a folder. */
export interface DriveFileRequest {
  readonly id: string;
  /** The link token; shown once. */
  readonly token: string;
}

/** The result of `uploadToRequest`. */
export type DriveRequestUpload =
  | { readonly passwordRequired: true }
  | {
      readonly passwordRequired: false;
      /** The new file. */
      readonly id: string;
      readonly attachmentId: string;
    };

/** Uploads the bytes of a file sent through a file request. */
export function putRequestFile(
  storage: AttachmentStorage,
  attachment: Attachment,
  file: Blob,
): AsyncResult<unknown> {
  const target = storage.from(attachment.bucket);

  if (!target.upload) {
    return AsyncResult.err(
      dbError("invalid_request", "The storage client has no upload", {
        hint: "DRIVE_STORAGE_CLIENT",
      }),
    );
  }

  return stored(
    target.upload(attachment.path, file, {
      contentType: attachment.mimeType,
      upsert: false,
    }),
  );
}
