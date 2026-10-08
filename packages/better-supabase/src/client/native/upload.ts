import type { DbError } from "../../core/errors.ts";
import type { UploadBody, UploadOptions } from "../../storage/bucket.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, toDbError } from "../../core/result.ts";

/** The part of a connected bucket `uploadFromUri` calls. */
export interface UriUploadTarget<T, R> {
  upload(target: T, body: UploadBody, options?: UploadOptions): AsyncResult<R>;
}

export interface UploadFromUriOptions extends UploadOptions {
  /** Defaults to the global `fetch`, which reads `file://` and `content://` URIs on React Native. */
  readonly fetch?: (uri: string) => Promise<Response>;
}

const TYPES: Readonly<Record<string, string>> = {
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
  gif: "image/gif",
  webp: "image/webp",
  heic: "image/heic",
  heif: "image/heif",
  mp4: "video/mp4",
  mov: "video/quicktime",
  m4a: "audio/mp4",
  mp3: "audio/mpeg",
  pdf: "application/pdf",
  json: "application/json",
  txt: "text/plain",
  csv: "text/csv",
};

/** The content type for a file URI's extension, ignoring a query or fragment. */
export function contentTypeOf(uri: string): string | undefined {
  const path = uri.split(/[?#]/, 1)[0] ?? uri;
  const dot = path.lastIndexOf(".");
  if (dot === -1 || dot < path.lastIndexOf("/")) return undefined;
  return TYPES[path.slice(dot + 1).toLowerCase()];
}

/**
 * Uploads a local file (an `expo-image-picker` or `expo-document-picker`
 * URI) to a connected bucket. The file is read into an `ArrayBuffer`, as
 * React Native's `Blob` can't be uploaded; the content type comes from the
 * option, the response or the extension.
 *
 * ```ts
 * const picked = await ImagePicker.launchImageLibraryAsync();
 * await uploadFromUri(avatars, { userId }, picked.assets[0].uri, { upsert: true });
 * ```
 */
export function uploadFromUri<T, R>(
  bucket: UriUploadTarget<T, R>,
  target: T,
  uri: string,
  options: UploadFromUriOptions = {},
): AsyncResult<R> {
  const { fetch: read = (value: string) => fetch(value), ...upload } = options;
  return AsyncResult.from(async () => {
    let body: ArrayBuffer;
    let type: string | undefined;
    try {
      const response = await read(uri);
      if (!response.ok) return err(unreadable(uri, response.status));
      type = response.headers.get("content-type") ?? undefined;
      body = await response.arrayBuffer();
    } catch (cause) {
      return err(toDbError(cause));
    }
    const contentType = upload.contentType ?? contentTypeOf(uri) ?? type;
    return bucket.upload(target, body, {
      ...upload,
      ...(contentType ? { contentType } : {}),
    });
  });
}

function unreadable(uri: string, status: number): DbError {
  return dbError(
    "invalid_input",
    `better-supabase: could not read ${uri} (status ${String(status)})`,
  );
}
