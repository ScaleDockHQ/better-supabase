import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { fromBase64, toBase64 } from "../../core/base64.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export interface DocumentsOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
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
  /**
   * Whether the caller may suggest changes: editors, and readers who hold
   * `documents.suggest`.
   */
  readonly canSuggest: boolean;
}

export interface DocumentVersion {
  readonly id: string;
  readonly number: number;
  /** The version's name; a named version is kept out of retention. */
  readonly label?: string;
  /** `manual` for a saved version, `auto` for one the app took. */
  readonly source: string;
  /** A frozen version keeps its name. */
  readonly frozen: boolean;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
}

export type DocumentSuggestionStatus =
  | "open"
  | "accepted"
  | "rejected"
  | "withdrawn";

/** A suggested change: a Yjs update that is not in the log yet. */
export interface DocumentSuggestion {
  readonly id: string;
  readonly documentId: string;
  readonly update: Uint8Array;
  readonly summary?: string;
  readonly status: DocumentSuggestionStatus;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly decidedBy?: string;
  readonly decidedAt?: Temporal.Instant;
  readonly note?: string;
}

export interface DecidedSuggestion extends DocumentSuggestion {
  /** The update's place in the log, when the suggestion was accepted. */
  readonly seq?: number;
}

export type SuggestionDecision = "accepted" | "rejected" | "withdrawn";

/** A document page in one read: `documents.page`. */
export interface DocumentPage extends OpenedDocument {
  /** Newest first; empty unless `versions` was asked for. */
  readonly versions: readonly DocumentVersion[];
  /** Open suggestions, oldest first; empty unless `suggestions` was asked for. */
  readonly suggestions: readonly DocumentSuggestion[];
}

export interface Documents {
  /** The document's state; creates it on first open for an editor. */
  open(ref: DocumentRef): AsyncResult<OpenedDocument>;
  /**
   * `open`, plus the versions (needs the versions module) and the open
   * suggestions when asked for, read together. Opening creates the document for
   * an editor, so the other two read after it.
   */
  page(
    ref: DocumentRef & {
      readonly versions?: boolean;
      readonly suggestions?: boolean;
    },
  ): AsyncResult<DocumentPage>;
  /** Appends an update and returns its sequence number. */
  push(input: { documentId: string; update: Uint8Array }): AsyncResult<number>;
  /**
   * Updates after `afterSeq`. When compaction dropped some of them, the result
   * carries the snapshot to start from instead.
   */
  pull(input: {
    documentId: string;
    afterSeq: number;
  }): AsyncResult<DocumentState>;
  /**
   * Stores `state` as the snapshot through `throughSeq` and drops those
   * updates. Returns false when a newer snapshot exists. The service role or
   * `documents.manage`.
   */
  compact(input: {
    documentId: string;
    state: Uint8Array;
    throughSeq: number;
  }): AsyncResult<boolean>;
  /** Saves the merged state as a version; needs the versions module. */
  saveVersion(input: {
    documentId: string;
    state: Uint8Array;
    label?: string | undefined;
  }): AsyncResult<{ readonly id: string; readonly number: number }>;
  /**
   * Newest first; needs the versions module. `named: true` keeps the versions
   * with a name.
   */
  versions(
    input: { documentId: string } & { readonly named?: boolean },
  ): AsyncResult<readonly DocumentVersion[]>;
  /**
   * Names a version, or removes its name with `null`. A named version is kept
   * out of retention. Editors; needs the versions module.
   */
  nameVersion(input: {
    documentId: string;
    versionId: string;
    label: string | null;
  }): AsyncResult<boolean>;
  /**
   * Stores an update as a suggestion instead of appending it. Editors, and
   * readers who hold `documents.suggest`.
   */
  suggest(input: {
    documentId: string;
    update: Uint8Array;
    summary?: string | undefined;
  }): AsyncResult<DocumentSuggestion>;
  /** Oldest first. Default status: `open`. */
  suggestions(input: {
    documentId: string;
    options?:
      | { readonly status?: DocumentSuggestionStatus | "all" }
      | undefined;
  }): AsyncResult<readonly DocumentSuggestion[]>;
  /**
   * Accepts or rejects a suggestion (editors), or withdraws it (its author).
   * Accepting appends the update to the log.
   */
  decideSuggestion(input: {
    suggestionId: string;
    decision: SuggestionDecision;
    note?: string | undefined;
  }): AsyncResult<DecidedSuggestion>;
  /** A saved state; needs the versions module. */
  version(input: {
    documentId: string;
    versionId: string;
  }): AsyncResult<Uint8Array>;
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
    canSuggest: row["canSuggest"] === true,
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
    source: optionalText(value["source"]) ?? "manual",
    frozen: value["frozen"] === true,
    createdAt: requiredInstant(value["createdAt"], "createdAt"),
    ...(label === undefined ? {} : { label }),
    ...(createdBy === undefined ? {} : { createdBy }),
  };
}

const SUGGESTION_STATUSES: ReadonlySet<string> = new Set([
  "open",
  "accepted",
  "rejected",
  "withdrawn",
]);

function isSuggestionStatus(value: unknown): value is DocumentSuggestionStatus {
  return typeof value === "string" && SUGGESTION_STATUSES.has(value);
}

function suggestionOf(value: unknown, fn: string): DecidedSuggestion {
  const row = recordOf(value, fn);
  const status = row["status"];

  if (!isSuggestionStatus(status)) {
    throw new TypeError(`${fn} returned an unknown status`);
  }

  const summary = optionalText(row["summary"]);
  const createdBy = optionalText(row["createdBy"]);
  const decidedBy = optionalText(row["decidedBy"]);
  const decidedAt = optionalInstant(row["decidedAt"]);
  const note = optionalText(row["note"]);

  const seq =
    row["seq"] === undefined || row["seq"] === null
      ? undefined
      : seqOf(row["seq"], "seq");

  return {
    id: textOf(row["id"]),
    documentId: textOf(row["documentId"]),
    update: fromBase64(textOf(row["update"])),
    status,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...(summary === undefined ? {} : { summary }),
    ...(createdBy === undefined ? {} : { createdBy }),
    ...(decidedBy === undefined ? {} : { decidedBy }),
    ...(decidedAt === undefined ? {} : { decidedAt }),
    ...(note === undefined ? {} : { note }),
    ...(seq === undefined ? {} : { seq }),
  };
}

/** The `documents` SQL module as typed calls, with updates as bytes. */
export function createDocuments(options: DocumentsOptions): Documents {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const client: Documents = {
    page: ({ versions, suggestions, ...ref }) =>
      AsyncResult.from<DocumentPage>(async () => {
        const opened = await hooked.open(ref);

        if (!opened.ok) {
          return err(opened.error);
        }

        const [versionList, suggestionList] = await Promise.all([
          versions
            ? hooked.versions({ documentId: opened.data.id })
            : Promise.resolve(ok<readonly DocumentVersion[]>([])),
          suggestions
            ? hooked.suggestions({ documentId: opened.data.id })
            : Promise.resolve(ok<readonly DocumentSuggestion[]>([])),
        ]);

        if (!versionList.ok) {
          return err(versionList.error);
        }

        if (!suggestionList.ok) {
          return err(suggestionList.error);
        }

        return ok({
          ...opened.data,
          versions: versionList.data,
          suggestions: suggestionList.data,
        });
      }),
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
    push: ({ documentId, update }) =>
      call(
        "push_document_update",
        { document_id: documentId, payload: toBase64(update) },
        (value) => seqOf(value, "push_document_update"),
      ),
    pull: ({ documentId, afterSeq }) =>
      call(
        "pull_document_updates",
        { document_id: documentId, after_seq: afterSeq },
        (value) => stateOf(value, "pull_document_updates"),
      ),
    compact: ({ documentId, state, throughSeq }) =>
      call(
        "compact_document",
        {
          document_id: documentId,
          state: toBase64(state),
          through_seq: throughSeq,
        },
        (value) => value === true,
      ),
    saveVersion: ({ documentId, state, label }) =>
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
    versions: ({ documentId, ...list }) =>
      call("list_document_versions", { document_id: documentId }, (value) =>
        recordsOf(value, "list_document_versions")
          .map(versionOf)
          .filter((item) => list.named !== true || item.label !== undefined),
      ),
    nameVersion: ({ documentId, versionId, label }) =>
      call(
        "name_document_version",
        { document_id: documentId, version_id: versionId, label },
        (value) => value === true,
      ),
    suggest: ({ documentId, update, summary }) =>
      call(
        "suggest_document_change",
        {
          document_id: documentId,
          payload: toBase64(update),
          summary: summary ?? null,
        },
        (value) => suggestionOf(value, "suggest_document_change"),
      ),
    suggestions: ({ documentId, options: list = {} }) =>
      call(
        "list_document_suggestions",
        { document_id: documentId, status: list.status ?? "open" },
        (value) =>
          recordsOf(value, "list_document_suggestions").map((item) =>
            suggestionOf(item, "list_document_suggestions"),
          ),
      ),
    decideSuggestion: ({ suggestionId, decision, note }) =>
      call(
        "decide_document_suggestion",
        { suggestion_id: suggestionId, decision, note: note ?? null },
        (value) => suggestionOf(value, "decide_document_suggestion"),
      ),
    version: ({ documentId, versionId }) =>
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

  // Helpers call the hooked client, so app hooks see each step.
  const hooked: Documents = withBlockHooks(client, options.hooks, {
    block: "documents",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
