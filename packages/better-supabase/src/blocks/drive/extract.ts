import type { BlockTransport } from "../../core/block-transport.ts";
import type { DbError } from "../../core/errors.ts";
import type { EventSink } from "../../events/index.ts";
import type { AttachmentBucket } from "../attachments/attachments.ts";
import type { Knowledge } from "../knowledge/knowledge.ts";
import type { JobHandler } from "../queue/types.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { stored } from "../attachments/attachments.ts";
import {
  blockCall,
  errorText,
  injectableOf,
  isRecord,
  optionalText,
  textOf,
} from "../shared.ts";

/** The file a `TextExtractor` reads: its node and its current content. */
export interface DriveTextFile {
  readonly nodeId: string;
  readonly organizationId: string;
  readonly name: string;
  readonly attachmentId: string;
  readonly mimeType: string;
  readonly size: number;
}

/**
 * Reads the text in a stored file, through any library or service (ADR 0036:
 * the SDK it calls is the app's dependency). An `apiVersion` other than 1 is
 * refused.
 */
export interface TextExtractor {
  readonly apiVersion?: 1;
  /** Stored with the text, such as `plain-text`. */
  readonly name: string;
  /**
   * The file's text, or undefined for a type it can't read. A throw fails the
   * extraction, so the job or event is retried.
   */
  extract(
    file: Blob,
    meta: DriveTextFile,
    signal?: AbortSignal,
  ): string | undefined | Promise<string | undefined>;
}

const TEXT_TYPES =
  /^(text\/|application\/(json|xml|yaml|x-yaml|ld\+json|x-ndjson)\b)/u;

const NAME = /^[a-z][a-z0-9_.-]{0,62}$/u;

/**
 * A `TextExtractor` without dependencies: it decodes `text/*`, JSON, XML and
 * YAML as UTF-8 and reads no other type.
 */
export function plainTextExtractor(): TextExtractor {
  return {
    apiVersion: 1,
    name: "plain-text",
    async extract(file, meta) {
      if (!TEXT_TYPES.test(meta.mimeType)) {
        return;
      }

      return new TextDecoder("utf-8").decode(await file.arrayBuffer());
    },
  };
}

/** Checks a `TextExtractor`'s version and name. */
export function textExtractorOf(extractor: TextExtractor): TextExtractor {
  injectableOf("The text extractor", extractor);

  if (!NAME.test(extractor.name)) {
    throw new TypeError(
      `The text extractor's name "${extractor.name}" must be lowercase letters, digits, dots, dashes or underscores`,
    );
  }

  return extractor;
}

/** The knowledge client methods `createDriveText` uses. */
export interface DriveTextKnowledge {
  readonly documents: Pick<Knowledge["documents"], "list" | "remove">;
  readonly ingest: Pick<Knowledge["ingest"], "text">;
}

export interface DriveTextOptions {
  /**
   * A service-role transport: `drive_text_source()` and `drive_set_text()` are
   * granted to `service_role` only.
   */
  readonly transport: BlockTransport;
  /** A service-role `supabase.storage`, to read the files. */
  readonly storage: {
    from(bucket: string): Pick<AttachmentBucket, "download">;
  };
  readonly extractor: TextExtractor;
  readonly schema?: string;
  /** Files larger than this are not read, and lose their text. Default 25 MB. */
  readonly maxFileBytes?: number;
  /**
   * A knowledge client on a service-role transport. Each file's text becomes
   * one subject-scoped document, replaced when the file changes, so only those
   * who can read the node find it.
   */
  readonly knowledge?: DriveTextKnowledge;
  /** `blocks.drive.options.subjectType`. Default `drive_node`. */
  readonly subjectType?: string;
  /** The outbox `typePrefix`. Default `dev.better-supabase`. */
  readonly typePrefix?: string;
}

/**
 * What an extraction did: stored the text, cleared it (no text, or a file too
 * large), or skipped the node (a folder, an unscanned file, or a newer revision
 * arrived meanwhile).
 */
export type DriveTextOutcome = "stored" | "cleared" | "skipped";

/** The payload `job` expects. */
export interface DriveTextJob {
  readonly nodeId: string;
}

export interface DriveText {
  /** Extracts and stores the text of a node's current content. */
  extract(nodeId: string, signal?: AbortSignal): AsyncResult<DriveTextOutcome>;
  /**
   * A jobs handler: `queue.work('drive-texts', text.job)`. Errors throw so the
   * queue retries.
   */
  readonly job: JobHandler<DriveTextJob>;
  /**
   * An outbox sink that extracts the text of each drive file whose upload is
   * confirmed clean (`attachment.uploaded` without scanning,
   * `attachment.scanned` with it), found by the attachment that is the file's
   * content. Errors throw so the relay retries.
   */
  sink(): EventSink;
}

const DEFAULT_MAX_FILE_BYTES = 26_214_400;

interface Source extends DriveTextFile {
  readonly bucket: string;
  readonly path: string;
  readonly status: string;
}

function sourceOf(value: unknown): Source | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  return {
    nodeId: textOf(value["nodeId"]),
    organizationId: textOf(value["organizationId"]),
    name: textOf(value["name"]),
    attachmentId: textOf(value["attachmentId"]),
    mimeType: optionalText(value["mimeType"]) ?? "application/octet-stream",
    size: Number(value["size"] ?? 0),
    bucket: textOf(value["bucket"]),
    path: textOf(value["path"]),
    status: textOf(value["status"]),
  };
}

const failed = (cause: unknown): DbError =>
  dbError("raised", `The text extraction failed: ${errorText(cause)}`, {
    hint: "DRIVE_TEXT_FAILED",
  });

/**
 * Extracts the text of drive files with the app's `TextExtractor`, stores it
 * for search through `drive_set_text`, and with `knowledge` keeps one
 * subject-scoped document per file. Replayed events and retried jobs are safe:
 * text for a revision that is no longer current is dropped.
 */
export function createDriveText(options: DriveTextOptions): DriveText {
  const extractor = textExtractorOf(options.extractor);
  const call = blockCall(options.transport, options.schema);
  const prefix = `${options.typePrefix ?? "dev.better-supabase"}.`;
  const subjectType = options.subjectType ?? "drive_node";
  const maxFileBytes = options.maxFileBytes ?? DEFAULT_MAX_FILE_BYTES;

  const save = (
    source: Source,
    content: string | undefined,
  ): AsyncResult<boolean> =>
    call(
      "drive_set_text",
      {
        node: source.nodeId,
        attachment: source.attachmentId,
        content: content ?? null,
        extractor: extractor.name,
      },
      (value) => value === true,
    );

  const index = (
    source: Source,
    content: string | undefined,
  ): AsyncResult<undefined> => {
    const { knowledge } = options;

    if (knowledge === undefined) {
      return AsyncResult.ok(undefined);
    }

    const subject = { type: subjectType, id: source.nodeId };

    return knowledge.documents
      .list(source.organizationId, { scope: "subject", subject })
      .andThen(async (documents) => {
        for (const document of documents) {
          const removed = await knowledge.documents.remove(document.id);

          if (!removed.ok) {
            return removed;
          }
        }

        if (content === undefined || content.trim() === "") {
          return ok(undefined);
        }

        const created = await knowledge.ingest.text(source.organizationId, {
          title: source.name,
          scope: "subject",
          subject,
          source: source.name,
          metadata: {
            nodeId: source.nodeId,
            attachmentId: source.attachmentId,
          },
          text: content,
        });

        return created.ok ? ok(undefined) : created;
      });
  };

  const store = (
    source: Source,
    content: string | undefined,
  ): AsyncResult<DriveTextOutcome> =>
    save(source, content).andThen((current) =>
      current
        ? index(source, content).map((): DriveTextOutcome =>
            content === undefined || content.trim() === ""
              ? "cleared"
              : "stored",
          )
        : AsyncResult.ok<DriveTextOutcome>("skipped"),
    );

  const run = (
    by: { readonly node: string } | { readonly attachment: string },
    signal?: AbortSignal,
  ): AsyncResult<DriveTextOutcome> =>
    call("drive_text_source", by, sourceOf).andThen((source) => {
      if (source?.status !== "clean") {
        return Promise.resolve(ok<DriveTextOutcome>("skipped"));
      }

      if (source.size > maxFileBytes) {
        return store(source, undefined);
      }

      return stored(
        options.storage.from(source.bucket).download(source.path),
      ).andThen(async (file) => {
        let text: string | undefined;

        try {
          text = await extractor.extract(file, source, signal);
        } catch (cause) {
          return err(failed(cause));
        }

        return store(source, text);
      });
    });

  return {
    extract: (nodeId, signal) => run({ node: nodeId }, signal),
    job: async (payload, _job, signal) => {
      await run({ node: payload.nodeId }, signal).orThrow();
    },
    sink: () => ({
      async send(events) {
        for (const event of events) {
          const type = event.type.startsWith(prefix)
            ? event.type.slice(prefix.length)
            : event.type;

          if (
            (type !== "attachment.uploaded" && type !== "attachment.scanned") ||
            !isRecord(event.data)
          ) {
            continue;
          }

          const subject = optionalText(event.data["subjectType"]);
          const attachment = optionalText(event.data["attachmentId"]);

          if (
            attachment !== undefined &&
            (subject === undefined || subject === subjectType)
          ) {
            await run({ attachment }).orThrow();
          }
        }
      },
    }),
  };
}
