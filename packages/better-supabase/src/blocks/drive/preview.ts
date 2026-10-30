import type { BlockTransport } from "../../core/block-transport.ts";
import type { DbError } from "../../core/errors.ts";
import type { EventSink } from "../../events/index.ts";
import type {
  Attachment,
  AttachmentStorage,
} from "../attachments/attachments.ts";
import type { JobHandler } from "../queue/types.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import type { DrivePreviews } from "./drive.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { eventTypeOf } from "../../events/cloud-event.ts";
import { attachmentOf, stored } from "../attachments/attachments.ts";
import { applyTemporal, blockCall, isRecord, optionalText } from "../shared.ts";
import { nodeOf, previewsOf } from "./parse.ts";

/** One rendered page: an image the drive stores under the file's previews. */
export interface PreviewPage {
  readonly body: Blob;
  /** Such as `image/webp` or `image/png`. */
  readonly contentType: string;
}

/** What the renderer gets with the file. */
export interface PreviewInput {
  readonly name: string;
  readonly mimeType: string;
  /** Render at most this many pages. */
  readonly maxPages: number;
  readonly signal?: AbortSignal;
}

/**
 * Renders a file's pages as images (a PDF rasterizer, an office converter, an
 * image resizer). Versioned: a breaking change to this contract ships a new
 * `apiVersion`. A file type the renderer doesn't handle returns `undefined`; a
 * throw fails the render so a job retries it.
 */
export interface PreviewRenderer {
  readonly apiVersion: 1;
  /** Such as `pdfium` or `libreoffice`. */
  readonly name: string;
  render(
    file: Blob,
    input: PreviewInput,
  ):
    | readonly PreviewPage[]
    | undefined
    | PromiseLike<readonly PreviewPage[] | undefined>;
}

/** Checks the renderer's `apiVersion` and name before the drive uses it. */
export function previewRendererOf(renderer: PreviewRenderer): PreviewRenderer {
  const version: unknown = renderer.apiVersion;

  if (version !== 1) {
    throw new TypeError(
      `preview renderer "${renderer.name}" targets preview renderer API ${String(version)}; this better-supabase supports 1. Upgrade better-supabase or use a release of the renderer for API 1.`,
    );
  }

  if (!/^[a-z][a-z0-9_-]{0,62}$/u.test(renderer.name)) {
    throw new TypeError(
      `preview renderer name "${renderer.name}" must be lowercase letters, digits, "-" or "_"`,
    );
  }

  return renderer;
}

export interface DrivePreviewsOptions extends BlockTemporalOptions {
  /**
   * A service-role transport: `drive_set_previews()` is granted to
   * `service_role` only.
   */
  readonly transport: BlockTransport;
  /** A service-role `supabase.storage`, to read files and store pages. */
  readonly storage: AttachmentStorage;
  readonly renderer: PreviewRenderer;
  readonly schema?: string;
  /** Default 20. */
  readonly maxPages?: number;
  /**
   * Render only files the attachments scanner marked `clean`. Without it,
   * `infected` and `failed` files are skipped and unscanned ones render.
   */
  readonly requireClean?: boolean;
  /** The drive's subject type on attachments. Default `drive_node`. */
  readonly subjectType?: string;
  /** The outbox `typePrefix`. Default `dev.better-supabase`. */
  readonly typePrefix?: string;
}

/** The payload `job` expects. */
export interface DrivePreviewJob {
  readonly nodeId: string;
}

export interface DrivePreviewService {
  /**
   * Renders the file's current content and records its pages. Returns
   * `undefined` when there is nothing to render: a folder, a file not uploaded
   * or not scanned yet, or a type the renderer skips.
   */
  render(
    nodeId: string,
    signal?: AbortSignal,
  ): AsyncResult<DrivePreviews | undefined>;
  /**
   * A jobs handler: `queue.work('drive-previews', previews.job)`. A deleted
   * node completes the job; other errors throw so the queue retries.
   */
  readonly job: JobHandler<DrivePreviewJob>;
  /**
   * An outbox sink that renders the file behind each `attachment.uploaded` and
   * `attachment.scanned` event on a drive node.
   */
  sink(): EventSink;
}

const nodeGone = (error: DbError): boolean => error.kind === "not_found";

/**
 * Renders drive files into preview pages with the app's renderer. Pages go to
 * the attachment's bucket under the drive's `previewPrefix`, which readers may
 * open while a download block keeps the original back.
 */
export function createDrivePreviews(
  options: DrivePreviewsOptions,
): DrivePreviewService {
  applyTemporal(options);
  const renderer = previewRendererOf(options.renderer);
  const call = blockCall(options.transport, options.schema);
  const maxPages = options.maxPages ?? 20;
  const subjectType = options.subjectType ?? "drive_node";
  const prefix = `${options.typePrefix ?? "dev.better-supabase"}.`;

  if (!Number.isInteger(maxPages) || maxPages < 1) {
    throw new TypeError("createDrivePreviews: maxPages must be 1 or more");
  }

  const renderable = (attachment: Attachment): boolean =>
    attachment.uploadedAt !== undefined &&
    (options.requireClean === true
      ? attachment.status === "clean"
      : attachment.status !== "infected" && attachment.status !== "failed");

  const record = (
    nodeId: string,
    attachmentId: string,
    pages: number,
  ): AsyncResult<DrivePreviews> =>
    call(
      "drive_set_previews",
      { node: nodeId, attachment: attachmentId, pages },
      (value) => previewsOf(value, "drive_set_previews"),
    );

  const store = (
    bucket: string,
    folder: string,
    pages: readonly PreviewPage[],
  ): AsyncResult<number> => {
    const bucketStore = options.storage.from(bucket);
    const upload = bucketStore.upload?.bind(bucketStore);

    if (upload === undefined) {
      return AsyncResult.err(
        dbError(
          "invalid_request",
          "createDrivePreviews needs a storage client that uploads",
          { hint: "DRIVE_STORAGE_CLIENT" },
        ),
      );
    }

    return AsyncResult.from(async () => {
      for (const [index, page] of pages.entries()) {
        const uploaded = await stored(
          upload(`${folder}/${String(index + 1)}`, page.body, {
            contentType: page.contentType,
            upsert: true,
          }),
        );

        if (!uploaded.ok) {
          return uploaded;
        }
      }

      return ok(pages.length);
    });
  };

  const render = (
    nodeId: string,
    signal?: AbortSignal,
  ): AsyncResult<DrivePreviews | undefined> =>
    call("drive_get", { node: nodeId }, (value) =>
      nodeOf(value, "drive_get"),
    ).andThen((node) => {
      const attachmentId = node.attachmentId;

      if (node.kind !== "file" || attachmentId === undefined) {
        return AsyncResult.ok(undefined);
      }

      return call("get_attachment", { id: attachmentId }, (value) =>
        isRecord(value) ? attachmentOf(value) : undefined,
      ).andThen((attachment) => {
        if (attachment === undefined || !renderable(attachment)) {
          return AsyncResult.ok(undefined);
        }

        return call("drive_previews", { node: nodeId }, (value) =>
          previewsOf(value, "drive_previews"),
        ).andThen((current) =>
          stored(
            options.storage.from(attachment.bucket).download(attachment.path),
          ).andThen(async (file) => {
            const pages = await renderer.render(file, {
              name: node.name,
              mimeType: attachment.mimeType,
              maxPages,
              ...(signal === undefined ? {} : { signal }),
            });

            if (pages === undefined) {
              return ok(undefined);
            }

            const kept = pages.slice(0, maxPages);
            const saved = await store(current.bucket, current.prefix, kept);

            return saved.ok
              ? record(nodeId, attachmentId, saved.data)
              : err(saved.error);
          }),
        );
      });
    });

  const settle = async (
    nodeId: string,
    signal?: AbortSignal,
  ): Promise<void> => {
    const rendered = render(nodeId, signal);
    const result = await rendered;

    if (result.ok || nodeGone(result.error)) {
      return;
    }

    await rendered.orThrow();
  };

  return {
    render,
    job: async (payload, _job, signal) => {
      await settle(payload.nodeId, signal);
    },
    sink: () => ({
      async send(events) {
        for (const event of events) {
          const type = eventTypeOf(event, prefix);

          if (
            (type !== "attachment.uploaded" && type !== "attachment.scanned") ||
            !isRecord(event.data) ||
            event.data["subjectType"] !== subjectType
          ) {
            continue;
          }

          const nodeId = optionalText(event.data["subjectId"]);

          if (nodeId !== undefined) {
            await settle(nodeId);
          }
        }
      },
    }),
  };
}
