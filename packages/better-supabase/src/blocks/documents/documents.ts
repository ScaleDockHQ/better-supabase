import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";

import { fromBase64, toBase64 } from "../../core/base64.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export interface DocumentsOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /** `blocks.documents.schema`, or the API schema of its wrappers. */
  readonly schema?: string;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: BlockHooks<Documents>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

/** Which document to open: one per subject and name. */
export interface DocumentRef {
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  /** Default: `body`. */
  readonly name?: string;
}

/** A Yjs update and its place in the document's log. */
export interface DocumentUpdate {
  readonly seq: number;
  readonly update: Uint8Array;
}

export interface DocumentInfo {
  readonly id: string;
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly name: string;
  /** The private realtime topic for updates and presence. */
  readonly topic: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** What a client needs to rebuild the document. */
export interface DocumentState {
  /** The compacted state; unset before the first compaction. */
  readonly snapshot?: Uint8Array;
  /** The last update the snapshot contains, `0` without one. */
  readonly snapshotSeq: number;
  /** The updates after the snapshot, oldest first. */
  readonly updates: readonly DocumentUpdate[];
}

export interface OpenedDocument extends DocumentInfo, DocumentState {
  /** Whether the caller may push updates. */
  readonly canWrite: boolean;
}

export interface DocumentVersion {
  readonly id: string;
  readonly number: number;
  readonly label?: string;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
}

export interface Documents {
  /** The document's state; creates it on first open for an editor. */
  open(ref: DocumentRef): AsyncResult<OpenedDocument>;
  /** Appends an update and returns its sequence number. */
  push(documentId: string, update: Uint8Array): AsyncResult<number>;
  /**
   * Updates after `afterSeq`. When compaction dropped some of them, the
   * result carries the snapshot to start from instead.
   */
  pull(documentId: string, afterSeq: number): AsyncResult<DocumentState>;
  /**
   * Stores `state` as the snapshot through `throughSeq` and drops those
   * updates. Returns false when a newer snapshot exists. The service role or
   * `documents.manage`.
   */
  compact(
    documentId: string,
    state: Uint8Array,
    throughSeq: number,
  ): AsyncResult<boolean>;
  /** Saves the merged state as a version; needs the versions module. */
  saveVersion(
    documentId: string,
    state: Uint8Array,
    label?: string,
  ): AsyncResult<{ readonly id: string; readonly number: number }>;
  /** Newest first; needs the versions module. */
  versions(documentId: string): AsyncResult<readonly DocumentVersion[]>;
  /** A saved state; needs the versions module. */
  version(documentId: string, versionId: string): AsyncResult<Uint8Array>;
  /** Documents with at least `minUpdates` uncompacted updates. Service role. */
  toCompact(options?: {
    readonly minUpdates?: number;
    readonly limit?: number;
  }): AsyncResult<readonly string[]>;
}

function seqOf(value: unknown, name: string): number {
  const seq = typeof value === "string" ? Number(value) : value;
  if (typeof seq !== "number" || !Number.isSafeInteger(seq) || seq < 0) {
    throw new TypeError(`${name} must be a sequence number`);
  }
  return seq;
}

function stateOf(value: unknown, fn: string): DocumentState {
  const row = recordOf(value, fn);
  const snapshot = optionalText(row["snapshot"]);
  return {
    snapshotSeq: seqOf(row["snapshotSeq"] ?? 0, "snapshotSeq"),
    updates: recordsOf(row["updates"], fn).map((item) => ({
      seq: seqOf(item["seq"], "seq"),
      update: fromBase64(textOf(item["update"])),
    })),
    ...(snapshot === undefined ? {} : { snapshot: fromBase64(snapshot) }),
  };
}

function openedOf(value: unknown): OpenedDocument {
  const row = recordOf(value, "open_document");
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    subjectType: textOf(row["subjectType"]),
    subjectId: textOf(row["subjectId"]),
    name: textOf(row["name"]),
    topic: textOf(row["topic"]),
    canWrite: row["canWrite"] === true,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...stateOf(row, "open_document"),
  };
}

function versionOf(value: Record<string, unknown>): DocumentVersion {
  const label = optionalText(value["label"]);
  const createdBy = optionalText(value["createdBy"]);
  return {
    id: textOf(value["id"]),
    number: seqOf(value["number"], "number"),
    createdAt: requiredInstant(value["createdAt"], "createdAt"),
    ...(label === undefined ? {} : { label }),
    ...(createdBy === undefined ? {} : { createdBy }),
  };
}

/** The `documents` SQL module as typed calls, with updates as bytes. */
export function createDocuments(options: DocumentsOptions): Documents {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const client: Documents = {
    open: (ref) =>
      call(
        "open_document",
        {
          tenant: ref.organizationId,
          subject_type: ref.subjectType,
          subject_id: ref.subjectId,
          name: ref.name ?? "body",
        },
        openedOf,
      ),
    push: (documentId, update) =>
      call(
        "push_document_update",
        { document_id: documentId, payload: toBase64(update) },
        (value) => seqOf(value, "push_document_update"),
      ),
    pull: (documentId, afterSeq) =>
      call(
        "pull_document_updates",
        { document_id: documentId, after_seq: afterSeq },
        (value) => stateOf(value, "pull_document_updates"),
      ),
    compact: (documentId, state, throughSeq) =>
      call(
        "compact_document",
        {
          document_id: documentId,
          state: toBase64(state),
          through_seq: throughSeq,
        },
        (value) => value === true,
      ),
    saveVersion: (documentId, state, label) =>
      call(
        "save_document_version",
        {
          document_id: documentId,
          state: toBase64(state),
          label: label ?? null,
        },
        (value) => {
          const row = recordOf(value, "save_document_version");
          return {
            id: textOf(row["id"]),
            number: seqOf(row["number"], "number"),
          };
        },
      ),
    versions: (documentId) =>
      call("list_document_versions", { document_id: documentId }, (value) =>
        recordsOf(value, "list_document_versions").map(versionOf),
      ),
    version: (documentId, versionId) =>
      call(
        "get_document_version",
        { document_id: documentId, version_id: versionId },
        (value) => fromBase64(textOf(value)),
      ),
    toCompact: (list = {}) =>
      call(
        "documents_to_compact",
        {
          ...(list.minUpdates === undefined
            ? {}
            : { min_updates: list.minUpdates }),
          ...(list.limit === undefined ? {} : { max_documents: list.limit }),
        },
        (value) =>
          (Array.isArray(value) ? value : []).map((id: unknown) => textOf(id)),
      ),
  };
  return withBlockHooks(client, options.hooks, {
    block: "documents",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
