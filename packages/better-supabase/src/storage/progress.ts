import type { UploadBody } from "./bucket.ts";

/** What `xhrUpload` needs from `XMLHttpRequest`, present in browsers and React Native. */
interface Xhr {
  open(method: string, url: string): void;
  setRequestHeader(name: string, value: string): void;
  send(body: unknown): void;
  abort(): void;
  readonly status: number;
  readonly responseText: string;
  onload: (() => void) | null;
  onerror: (() => void) | null;
  onabort: (() => void) | null;
  readonly upload: {
    onprogress:
      | ((event: {
          readonly loaded: number;
          readonly total: number;
          readonly lengthComputable: boolean;
        }) => void)
      | null;
  };
}

type XhrConstructor = new () => Xhr;

/** The runtime's `XMLHttpRequest`, or `undefined` (Node, workers). */
export function xhrConstructor(): XhrConstructor | undefined {
  // SAFETY: a global XMLHttpRequest is the browser or React Native constructor.
  const runtime = globalThis as { XMLHttpRequest?: XhrConstructor };
  return typeof runtime.XMLHttpRequest === "function"
    ? runtime.XMLHttpRequest
    : undefined;
}

/** Bodies `XMLHttpRequest.send` takes; streams go through storage-js instead. */
export function sendable(body: UploadBody): boolean {
  return !(
    typeof ReadableStream !== "undefined" && body instanceof ReadableStream
  );
}

export interface XhrUploadOptions {
  readonly contentType?: string | undefined;
  readonly cacheControl?: string | undefined;
  readonly upsert: boolean;
  readonly signal?: AbortSignal | undefined;
  readonly onProgress: (fraction: number) => void;
}

/** The parsed error body of a failed signed upload, for `fromStorageError`. */
export interface XhrFailure {
  readonly message: string;
  readonly statusCode: string;
  readonly name?: string;
}

/**
 * PUTs `body` to a signed upload URL with upload progress events. Resolves
 * with `undefined` on success or the failure to map.
 */
export function xhrUpload(
  Request: XhrConstructor,
  url: string,
  body: UploadBody,
  options: XhrUploadOptions,
): Promise<XhrFailure | undefined> {
  return new Promise((resolve) => {
    const xhr = new Request();
    const onAbort = () => {
      xhr.abort();
    };
    const done = (failure: XhrFailure | undefined) => {
      options.signal?.removeEventListener("abort", onAbort);
      resolve(failure);
    };
    xhr.open("PUT", url);
    xhr.setRequestHeader("x-upsert", String(options.upsert));
    xhr.setRequestHeader(
      "cache-control",
      `max-age=${options.cacheControl ?? "3600"}`,
    );
    const type =
      options.contentType ??
      (typeof Blob !== "undefined" && body instanceof Blob && body.type
        ? body.type
        : undefined);
    if (type) xhr.setRequestHeader("content-type", type);
    xhr.upload.onprogress = (event) => {
      if (event.lengthComputable && event.total > 0)
        options.onProgress(Math.min(1, event.loaded / event.total));
    };
    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        options.onProgress(1);
        done(undefined);
        return;
      }
      done(parseFailure(xhr.status, xhr.responseText));
    };
    xhr.onerror = () => {
      done({
        message: "Upload failed",
        statusCode: "0",
        name: "StorageUnknownError",
      });
    };
    xhr.onabort = () => {
      done({
        message: "The upload was aborted",
        statusCode: "0",
        name: "AbortError",
      });
    };
    options.signal?.addEventListener("abort", onAbort, { once: true });
    xhr.send(body);
  });
}

function parseFailure(status: number, text: string): XhrFailure {
  let message = `Upload failed with status ${String(status)}`;
  let statusCode = String(status);
  try {
    const parsed: unknown = JSON.parse(text);
    if (typeof parsed === "object" && parsed !== null) {
      // SAFETY: an object; each field read is type-checked below.
      const fields = parsed as { message?: unknown; statusCode?: unknown };
      if (typeof fields.message === "string") message = fields.message;
      if (typeof fields.statusCode === "string") statusCode = fields.statusCode;
    }
  } catch {
    // a non-JSON error body keeps the status message
  }
  return { message, statusCode };
}
