import type { AsyncResult } from "../../core/result.ts";
import type { BlockCall } from "../shared.ts";
import type { DriveNode } from "./drive.ts";

import { temporal } from "../../core/temporal-required.ts";
import {
  enumOrThrow,
  optionalInstant,
  optionalText,
  recordOf,
  textOf,
} from "../shared.ts";

const DOCUMENT_STATUSES = [
  "draft",
  "in_review",
  "effective",
  "obsolete",
] as const;

/** Where a controlled document is in its release workflow. */
export type DriveDocumentStatus = (typeof DOCUMENT_STATUSES)[number];

/**
 * A file under document control, with `blocks.drive.options.control`: its
 * number, type, owner, effective version and review date.
 */
export interface DriveDocument {
  /** The number from the numbering block, such as `DOC-00012`. */
  readonly number: string;
  /** One of `options.control.types`. */
  readonly type: string;
  readonly status: DriveDocumentStatus;
  readonly ownerId: string | undefined;
  /** The version that readers get; `undefined` until the first release. */
  readonly effectiveVersionId: string | undefined;
  /** Its revision number. */
  readonly effectiveVersion: number | undefined;
  /** The attachment of the effective version. */
  readonly effectiveAttachmentId: string | undefined;
  readonly effectiveFrom: Temporal.Instant | undefined;
  /** The document's own interval; `options.control.reviewMonths` otherwise. */
  readonly reviewIntervalMonths: number | undefined;
  readonly nextReviewOn: Temporal.PlainDate | undefined;
  /** An effective document whose review date has come. */
  readonly reviewDue: boolean;
  /**
   * The caller is below the write role, so downloads and previews give only the
   * effective version, never the working copy.
   */
  readonly effectiveOnly: boolean;
}

export interface DriveDocumentInput {
  /** One of `options.control.types`. */
  readonly type: string;
  /** A member of the organization; the caller when the document has none. */
  readonly ownerId?: string;
  /** Months between reviews, from 1 to 120. */
  readonly reviewIntervalMonths?: number;
}

/** Filters for the document register. */
export interface DriveDocumentFilters {
  readonly type?: string;
  readonly status?: DriveDocumentStatus;
  readonly ownerId?: string;
  /** Only effective documents whose review date has come. */
  readonly reviewDue?: boolean;
  /** Part of the number or the name. */
  readonly search?: string;
}

/** The controlled document calls of the drive client. */
export interface DriveDocuments<N> {
  /**
   * Puts a file under document control, or changes its type, owner or review
   * interval. A new document gets its number and starts as a draft.
   */
  saveDocument(id: string, document: DriveDocumentInput): AsyncResult<N>;
  /**
   * Sends a draft or an effective document for release: `attachmentId`, or the
   * current version. An approval request with action `release` goes to
   * approvals, and its approval releases the version. A draft moves to
   * `in_review`; an effective document stays effective on its released version
   * until the revision is approved.
   */
  submitDocument(
    id: string,
    options?: { readonly attachmentId?: string; readonly reason?: string },
  ): AsyncResult<N>;
  /** Service role: releases `attachmentId` of a document in review or effective. */
  releaseDocument(id: string, attachmentId: string): AsyncResult<N>;
  /** Withdraws an effective document; needs `options.control.releaseRole`. */
  obsoleteDocument(id: string, reason: string): AsyncResult<N>;
  /**
   * Records a periodic review: `unchanged` moves the next review date on,
   * `revise` leaves the document effective until a new version is released.
   */
  reviewDocument(
    id: string,
    outcome: "unchanged" | "revise",
    note?: string,
  ): AsyncResult<N>;
  /** The organization's document register, by number. */
  documents(
    organizationId: string,
    filters?: DriveDocumentFilters,
  ): AsyncResult<readonly N[]>;
  /** Service role: reports the documents whose review is due, once per date. */
  notifyDueReviews(): AsyncResult<number>;
}

const optionalNumber = (value: unknown): number | undefined =>
  typeof value === "number" ? value : undefined;

export function documentOf(value: unknown): DriveDocument {
  const row = recordOf(value, "drive_node_json");
  const next = optionalText(row["nextReviewOn"]);

  return {
    number: textOf(row["number"]),
    type: textOf(row["type"]),
    status: enumOrThrow(row["status"], DOCUMENT_STATUSES, "document status"),
    ownerId: optionalText(row["ownerId"]),
    effectiveVersionId: optionalText(row["effectiveVersionId"]),
    effectiveVersion: optionalNumber(row["effectiveVersion"]),
    effectiveAttachmentId: optionalText(row["effectiveAttachmentId"]),
    effectiveFrom: optionalInstant(row["effectiveFrom"]),
    reviewIntervalMonths: optionalNumber(row["reviewIntervalMonths"]),
    nextReviewOn:
      next === undefined ? undefined : temporal().PlainDate.from(next),
    reviewDue: row["reviewDue"] === true,
    effectiveOnly: row["effectiveOnly"] === true,
  };
}

export function driveDocuments(
  call: BlockCall,
  nodeOf: (value: unknown, fn: string) => DriveNode,
  nodesOf: (value: unknown, fn: string) => readonly DriveNode[],
): DriveDocuments<DriveNode> {
  const node =
    (fn: string) =>
    (value: unknown): DriveNode =>
      nodeOf(value, fn);

  return {
    saveDocument: (id, document) =>
      call(
        "drive_document_save",
        {
          node: id,
          document_type: document.type,
          owner_id: document.ownerId ?? null,
          review_interval_months: document.reviewIntervalMonths ?? null,
        },
        node("drive_document_save"),
      ),
    submitDocument: (id, submit = {}) =>
      call(
        "drive_document_submit",
        {
          node: id,
          attachment: submit.attachmentId ?? null,
          reason: submit.reason ?? null,
        },
        node("drive_document_submit"),
      ),
    releaseDocument: (id, attachmentId) =>
      call(
        "drive_document_release",
        { node: id, attachment: attachmentId },
        node("drive_document_release"),
      ),
    obsoleteDocument: (id, reason) =>
      call(
        "drive_document_obsolete",
        { node: id, reason },
        node("drive_document_obsolete"),
      ),
    reviewDocument: (id, outcome, note) =>
      call(
        "drive_document_review",
        { node: id, outcome, note: note ?? null },
        node("drive_document_review"),
      ),
    documents: (organizationId, filters = {}) =>
      call("drive_documents", { tenant: organizationId, filters }, (value) =>
        nodesOf(value, "drive_documents"),
      ),
    notifyDueReviews: () => call("notify_due_drive_reviews", {}, Number),
  };
}
