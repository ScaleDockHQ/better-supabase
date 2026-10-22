import type { DbError } from "../../core/errors.ts";
import type { Result } from "../../core/result.ts";
import type { Controller } from "../controller.ts";
import type { AttachmentStatus, NewAttachment } from "./attachments.ts";

import { dbError } from "../../core/errors.ts";
import { err, ok, toDbError } from "../../core/result.ts";
import { defineController } from "../controller.ts";

/** Where `start` told the browser to send the bytes. */
export interface AttachmentUploadTicket {
  readonly id: string;
  /** The signed upload URL from `attachments.upload` or `replace`. */
  readonly signedUrl: string;
}

/** What `confirm` and `refresh` answer: `null` when the caller can't tell. */
export type AttachmentScanState = { readonly status: AttachmentStatus } | null;

/** One file to upload. */
export interface AttachmentFileInput {
  readonly file: Blob;
  readonly name: string;
  /** Default the blob's `type`, or `application/octet-stream`. */
  readonly mimeType?: string;
  readonly width?: number;
  readonly height?: number;
  readonly pages?: number;
}

/**
 * Sends `body` to the signed URL and reports the share sent, from 0 to 1. The
 * default PUTs it with `XMLHttpRequest`, which React DOM and React Native both
 * have.
 */
export type AttachmentSend = (
  ticket: AttachmentUploadTicket,
  body: Blob,
  progress: (fraction: number) => void,
  signal: AbortSignal,
) => Promise<Result<null>>;

export interface AttachmentUploadControllerOptions {
  /**
   * Creates the pending record and signs the upload:
   * `attachments.upload(subject, file)`, or a server action that calls it.
   */
  readonly start: (
    file: NewAttachment,
  ) => PromiseLike<Result<AttachmentUploadTicket>>;
  /** Marks the upload done: `attachments.confirm(id)`, or a server action. */
  readonly confirm: (id: string) => PromiseLike<Result<AttachmentScanState>>;
  /**
   * Reads the file's scan status again, so an upload waits in `scanning` until
   * the scanner answers. Without it an upload ends once confirmed.
   */
  readonly refresh?: (id: string) => PromiseLike<Result<AttachmentScanState>>;
  readonly send?: AttachmentSend;
  /** Milliseconds between scan checks. Default 2000. */
  readonly pollInterval?: number;
  /** Runs once a file is uploaded (and scanned clean, with `refresh`). */
  readonly onUploaded?: (id: string) => void | Promise<void>;
}

export type AttachmentUploadStatus =
  | "uploading"
  | "confirming"
  | "scanning"
  | "done"
  | "blocked"
  | "error";

export interface AttachmentUploadItem {
  /** A local key, stable for the upload's life. */
  readonly key: string;
  readonly name: string;
  readonly mimeType: string;
  readonly size: number;
  readonly status: AttachmentUploadStatus;
  /** The share of the bytes sent, from 0 to 1. */
  readonly progress: number;
  /** The attachment id once `start` created the record. */
  readonly id: string | undefined;
  readonly error: DbError | undefined;
}

export interface AttachmentUploadSnapshot {
  readonly uploads: readonly AttachmentUploadItem[];
  /** Whether any upload is still sending, confirming or waiting for its scan. */
  readonly busy: boolean;
}

export interface AttachmentUploadActions {
  /** Starts uploading each file, side by side. */
  readonly add: (files: readonly AttachmentFileInput[]) => void;
  /** Starts a failed upload again from the beginning. */
  readonly retry: (key: string) => void;
  /** Stops an upload and drops it from the list. */
  readonly dismiss: (key: string) => void;
  /** Drops the uploads that ended. */
  readonly clear: () => void;
}

export type AttachmentUploadController = Controller<
  AttachmentUploadSnapshot,
  AttachmentUploadActions
>;

/** `XMLHttpRequest`, typed structurally so the module needs no DOM types. */
interface Xhr {
  open(method: string, url: string): void;
  setRequestHeader(name: string, value: string): void;
  send(body: Blob): void;
  abort(): void;
  readonly status: number;
  readonly upload: {
    addEventListener(
      type: "progress",
      listener: (event: { loaded: number; total: number }) => void,
    ): void;
  };
  addEventListener(
    type: "load" | "error" | "abort",
    listener: () => void,
  ): void;
}

const uploadFailed = (status?: number): DbError =>
  dbError(
    "network",
    status === undefined
      ? "The upload did not reach Storage"
      : `Storage refused the upload (${String(status)})`,
    { hint: "ATTACHMENT_UPLOAD_FAILED" },
  );

/** The default `send`: a PUT to the signed URL with upload progress. */
export const xhrSend: AttachmentSend = (ticket, body, progress, signal) =>
  new Promise((resolve) => {
    // SAFETY: React DOM and React Native define XMLHttpRequest with this shape.
    const Request = (globalThis as { XMLHttpRequest?: new () => Xhr })
      .XMLHttpRequest;

    if (Request === undefined) {
      resolve(
        err(
          dbError("invalid_request", "This runtime has no XMLHttpRequest", {
            hint: "ATTACHMENT_UPLOAD_FAILED",
          }),
        ),
      );

      return;
    }

    const request = new Request();
    request.open("PUT", ticket.signedUrl);
    request.setRequestHeader("x-upsert", "false");

    if (body.type !== "") {
      request.setRequestHeader("content-type", body.type);
    }

    request.upload.addEventListener("progress", (event) => {
      if (event.total > 0) {
        progress(event.loaded / event.total);
      }
    });
    request.addEventListener("load", () => {
      resolve(
        request.status >= 200 && request.status < 300
          ? ok(null)
          : err(uploadFailed(request.status)),
      );
    });
    request.addEventListener("error", () => {
      resolve(err(uploadFailed()));
    });
    request.addEventListener("abort", () => {
      resolve(err(dbError("aborted", "The upload was stopped")));
    });

    signal.addEventListener("abort", () => {
      request.abort();
    });
    request.send(body);
  });

const ENDED: ReadonlySet<AttachmentUploadStatus> = new Set([
  "done",
  "blocked",
  "error",
]);

const scanFailed = (): DbError =>
  dbError("raised", "The malware scan failed", {
    hint: "ATTACHMENT_SCAN_FAILED",
  });

/**
 * Uploads files to a record: each one is created (`start`), sent to its signed
 * URL with progress (`send`), confirmed (`confirm`) and, with `refresh`,
 * watched until the scan answers. Uploads run side by side; a failed one stays
 * in the list with its error until it is retried or dismissed.
 */
export function createAttachmentUploadController(
  options: AttachmentUploadControllerOptions,
): AttachmentUploadController {
  const send = options.send ?? xhrSend;
  const interval = options.pollInterval ?? 2000;

  return defineController<AttachmentUploadSnapshot, AttachmentUploadActions>(
    { uploads: [], busy: false },
    (state) => {
      let counter = 0;
      const inputs = new Map<string, AttachmentFileInput>();
      const aborts = new Map<string, AbortController>();
      const timers = new Set<ReturnType<typeof setTimeout>>();

      const patch = (key: string, change: Partial<AttachmentUploadItem>) => {
        state.set((current) => {
          const uploads = current.uploads.map((item) =>
            item.key === key ? { ...item, ...change } : item,
          );

          return {
            uploads,
            busy: uploads.some((item) => !ENDED.has(item.status)),
          };
        });
      };

      const alive = (key: string, signal: AbortSignal): boolean =>
        !signal.aborted && inputs.has(key);

      const finish = async (key: string, id: string): Promise<void> => {
        patch(key, { status: "done", progress: 1 });

        try {
          await options.onUploaded?.(id);
        } catch (cause) {
          patch(key, { error: toDbError(cause) });
        }
      };

      const settle = async (
        key: string,
        id: string,
        scan: AttachmentScanState,
        signal: AbortSignal,
      ): Promise<void> => {
        if (!alive(key, signal)) {
          return;
        }

        if (scan?.status === "infected") {
          patch(key, { status: "blocked" });

          return;
        }

        if (scan?.status === "failed") {
          patch(key, { status: "error", error: scanFailed() });

          return;
        }

        if (
          scan === null ||
          scan.status === "clean" ||
          options.refresh === undefined
        ) {
          await finish(key, id);

          return;
        }

        patch(key, { status: "scanning" });
        const { refresh } = options;

        const timer = setTimeout(() => {
          timers.delete(timer);
          void Promise.resolve(refresh(id)).then(async (next) => {
            if (!next.ok) {
              if (alive(key, signal)) {
                patch(key, { status: "error", error: next.error });
              }

              return;
            }

            await settle(key, id, next.data, signal);
          });
        }, interval);

        timers.add(timer);
      };

      const run = async (key: string): Promise<void> => {
        const input = inputs.get(key);

        if (input === undefined) {
          return;
        }

        const abort = new AbortController();
        aborts.get(key)?.abort();
        aborts.set(key, abort);
        const { signal } = abort;

        patch(key, {
          status: "uploading",
          progress: 0,
          error: undefined,
          id: undefined,
        });

        const fail = (error: DbError): void => {
          if (alive(key, signal)) {
            patch(key, { status: "error", error });
          }
        };

        const started = await options.start({
          name: input.name,
          mimeType: mimeOf(input),
          size: input.file.size,
          ...(input.width === undefined ? {} : { width: input.width }),
          ...(input.height === undefined ? {} : { height: input.height }),
          ...(input.pages === undefined ? {} : { pages: input.pages }),
        });

        if (!started.ok) {
          fail(started.error);

          return;
        }

        const ticket = started.data;

        if (!alive(key, signal)) {
          return;
        }

        patch(key, { id: ticket.id });

        const sent = await send(
          ticket,
          input.file,
          (fraction) => {
            if (alive(key, signal)) {
              patch(key, { progress: Math.min(1, Math.max(0, fraction)) });
            }
          },
          signal,
        );

        if (!sent.ok) {
          fail(sent.error);

          return;
        }

        if (!alive(key, signal)) {
          return;
        }

        patch(key, { status: "confirming", progress: 1 });
        const confirmed = await options.confirm(ticket.id);

        if (!confirmed.ok) {
          fail(confirmed.error);

          return;
        }

        await settle(key, ticket.id, confirmed.data, signal);
      };

      const add = (files: readonly AttachmentFileInput[]): void => {
        const added = files.map((input): AttachmentUploadItem => {
          counter += 1;
          const key = `upload-${String(counter)}`;
          inputs.set(key, input);

          return {
            key,
            name: input.name,
            mimeType: mimeOf(input),
            size: input.file.size,
            status: "uploading",
            progress: 0,
            id: undefined,
            error: undefined,
          };
        });

        if (added.length === 0) {
          return;
        }

        state.set((current) => ({
          uploads: [...current.uploads, ...added],
          busy: true,
        }));

        for (const item of added) {
          void run(item.key);
        }
      };

      const drop = (keep: (item: AttachmentUploadItem) => boolean): void => {
        state.set((current) => {
          const uploads = current.uploads.filter((item) => {
            if (keep(item)) {
              return true;
            }

            inputs.delete(item.key);
            aborts.get(item.key)?.abort();
            aborts.delete(item.key);

            return false;
          });

          return {
            uploads,
            busy: uploads.some((item) => !ENDED.has(item.status)),
          };
        });
      };

      return {
        actions: {
          add,
          retry: (key) => {
            const item = state.get().uploads.find((each) => each.key === key);

            if (item?.status === "error") {
              void run(key);
            }
          },
          dismiss: (key) => {
            drop((item) => item.key !== key);
          },
          clear: () => {
            drop((item) => !ENDED.has(item.status));
          },
        },
        start: () => {
          for (const item of state.get().uploads) {
            const signal = aborts.get(item.key)?.signal;

            if (item.status === "scanning" && item.id !== undefined && signal) {
              void settle(item.key, item.id, { status: "pending" }, signal);
            }
          }

          return () => {
            for (const timer of timers) {
              clearTimeout(timer);
            }

            timers.clear();
          };
        },
      };
    },
  );
}

const mimeOf = (input: AttachmentFileInput): string =>
  input.mimeType ?? (input.file.type || "application/octet-stream");
