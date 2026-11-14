import type { AsyncResult } from "../../core/result.ts";
import type { FileStore } from "../../storage/file-store.ts";
import type { Attachment } from "../attachments/attachments.ts";
import type { UploadTicket } from "../attachments/files.ts";

import { hinted } from "../attachments/files.ts";

/**
 * A file from a caller who may only add files to the folder: PUT the bytes to
 * `signedUrl`, then call `commitContribution`. It carries the new file's id and
 * no node, because the caller can't read it.
 */
export interface DriveContribution extends UploadTicket {
  readonly id: string;
  readonly attachment: Attachment;
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
  files: FileStore,
  attachment: Attachment,
  file: Blob,
): AsyncResult<unknown> {
  return files
    .put(attachment.bucket, attachment.path, file, {
      contentType: attachment.mimeType,
      upsert: false,
    })
    .mapError(hinted("DRIVE_STORAGE_CLIENT"));
}
