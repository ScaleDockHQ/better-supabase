"use client";

import type { SubjectRef } from "../../../schema/types.ts";
import type {
  AttachmentSend,
  AttachmentUploadActions,
  AttachmentUploadControllerOptions,
  AttachmentUploadSnapshot,
} from "../client.ts";

import { envBlockOptions } from "../../block-env-options.ts";
import { useController, useLatest } from "../../react-controller.ts";
import { useBlockEnv, useBlockTenant } from "../../react-env.ts";
import { createAttachments } from "../attachments.ts";
import { createAttachmentUploadController, xhrSend } from "../client.ts";

export type {
  AttachmentFileInput,
  AttachmentScanState,
  AttachmentSend,
  AttachmentUploadItem,
  AttachmentUploadStatus,
  AttachmentUploadTicket,
} from "../client.ts";

export interface UseAttachmentUploadOptions {
  /** The record the files go to; `null` for files without one. */
  readonly subject: SubjectRef | null;
  /**
   * Creates the record and signs the upload. Default `attachments.upload`
   * through the browser client; pass a server action to create it on the
   * server.
   */
  readonly start?: AttachmentUploadControllerOptions["start"];
  /** Default `attachments.confirm` through the browser client. */
  readonly confirm?: AttachmentUploadControllerOptions["confirm"];
  /**
   * Reads the scan status while it runs. Default `attachments.get` through the
   * browser client when `start` is not given; `false` ends an upload once
   * confirmed.
   */
  readonly refresh?: AttachmentUploadControllerOptions["refresh"] | false;
  readonly send?: AttachmentSend;
  /** Milliseconds between scan checks. Default 2000. */
  readonly pollInterval?: number;
  /** Runs once a file is uploaded (and scanned clean, while watched). */
  readonly onUploaded?: (id: string) => void | Promise<void>;
}

export interface AttachmentUploadState
  extends AttachmentUploadSnapshot, AttachmentUploadActions {}

/**
 * Uploads files to a record with progress: each file is created, sent to its
 * signed URL, confirmed and watched until the malware scan answers. It acts in
 * the client's tenant with the names in the client's `blocks` config. The same
 * hook runs in React DOM and React Native.
 *
 * ```tsx
 * const { uploads, add } = useAttachmentUpload({
 *   subject: { type: "task", id: taskId },
 * });
 * <input
 *   type="file"
 *   onChange={(event) =>
 *     add(
 *       [...(event.target.files ?? [])].map((file) => ({
 *         file,
 *         name: file.name,
 *       })),
 *     )
 *   }
 * />;
 * ```
 */
export function useAttachmentUpload(
  options: UseAttachmentUploadOptions,
): AttachmentUploadState {
  const env = useBlockEnv();
  const tenant = useBlockTenant(env);
  const latest = useLatest(options);
  const type = options.subject?.type;
  const id = options.subject?.id;

  const watch =
    options.refresh === false
      ? "off"
      : typeof options.refresh === "function"
        ? "own"
        : options.start === undefined
          ? "client"
          : "off";

  const { pollInterval } = options;

  return useController(() => {
    const client = createAttachments({
      ...envBlockOptions(env, "attachments"),
      storage: env.supabase.storage,
      ...(tenant === undefined ? {} : { tenant }),
    });

    const subject: SubjectRef | null =
      type === undefined || id === undefined ? null : { type, id };

    const scanOf = (file: string) =>
      client.get(file).map((attachment) => ({ status: attachment.status }));

    const refresh = (file: string) => {
      const own = latest.current.refresh;

      return typeof own === "function" ? own(file) : scanOf(file);
    };

    return createAttachmentUploadController({
      start: (file) =>
        latest.current.start?.(file) ??
        client
          .upload(subject, file)
          .map((upload) => ({
            id: upload.attachment.id,
            signedUrl: upload.signedUrl,
          })),
      confirm: (file) =>
        latest.current.confirm?.(file) ??
        client
          .confirm(file)
          .map((attachment) => ({ status: attachment.status })),
      ...(watch === "off" ? {} : { refresh }),
      send: (ticket, body, progress, signal) =>
        (latest.current.send ?? xhrSend)(ticket, body, progress, signal),
      ...(pollInterval === undefined ? {} : { pollInterval }),
      onUploaded: async (file) => {
        await latest.current.onUploaded?.(file);
      },
    });
  }, [env, tenant, type, id, watch, pollInterval, latest]).view;
}
