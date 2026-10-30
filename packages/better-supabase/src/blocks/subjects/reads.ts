import type { BlockCall } from "../../core/block-helpers.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { RecordRef } from "../../schema/types.ts";

import {
  instantArg,
  optionalInstant,
  optionalText,
  recordOf,
} from "../shared.ts";

/** The most entries one `reads.list` call returns. */
export const SUBJECT_ACCESS_LOG_LIMIT = 500;

/** One logged read of a record, from `subject_access_log`. */
export interface SubjectRead {
  /** The audit entry. */
  readonly id: string;
  /** Who read the record. */
  readonly actorId?: string;
  /** Their name, or their email without one. */
  readonly actorName?: string;
  readonly at: Temporal.Instant;
  /** Why they read it, when they gave a purpose. */
  readonly purpose?: string;
  /** They held emergency access to the record. */
  readonly emergency: boolean;
  /** The block and the read function that returned the record. */
  readonly block?: string;
  readonly function?: string;
}

export interface SubjectReadOptions {
  /** Why the record is read, such as `treatment`; at most 500 characters. */
  readonly purpose?: string;
}

export interface SubjectAccessLogOptions {
  /** Only reads at or after this instant. */
  readonly since?: Temporal.Instant;
  /** Default 100, at most 500. */
  readonly limit?: number;
}

/** The read log of records whose type has `auditReads` (ADR 0134). */
export interface SubjectReads {
  /**
   * Logs a read of the record by the caller, for a screen that shows it without
   * a block read function, such as a page that selects the row itself. A type
   * without `auditReads` logs nothing.
   */
  log(subject: RecordRef, options?: SubjectReadOptions): AsyncResult<void>;
  /**
   * Who read the record and when, newest first. For holders of `audit.read`,
   * the record team's leads, the record's own guest and a representative with
   * `act` authority.
   */
  list(
    subject: RecordRef,
    options?: SubjectAccessLogOptions,
  ): AsyncResult<readonly SubjectRead[]>;
}

function readOf(value: unknown): SubjectRead {
  const row = recordOf(value, "subject read");
  const actorId = optionalText(row["actorId"]);
  const actorName = optionalText(row["actorName"]);
  const purpose = optionalText(row["purpose"]);
  const block = optionalText(row["block"]);
  const fn = optionalText(row["function"]);
  const at = optionalInstant(row["at"]);

  if (at === undefined) {
    throw new TypeError("subject read: at must be an instant");
  }

  return {
    id: optionalText(row["id"]) ?? "",
    ...(actorId === undefined ? {} : { actorId }),
    ...(actorName === undefined ? {} : { actorName }),
    at,
    ...(purpose === undefined ? {} : { purpose }),
    emergency: row["emergency"] === true,
    ...(block === undefined ? {} : { block }),
    ...(fn === undefined ? {} : { function: fn }),
  };
}

const readList = (value: unknown): SubjectRead[] =>
  (Array.isArray(value) ? value : []).map(readOf);

/** `reads` of the subjects client, over `call`. */
export function subjectReads(call: BlockCall): SubjectReads {
  return {
    log: (subject, options = {}) =>
      call(
        "record_subject_read",
        {
          subject_type: subject.type,
          subject_id: subject.id,
          purpose: options.purpose ?? null,
        },
        () => undefined,
      ),
    list: (subject, options = {}) =>
      call(
        "subject_access_log",
        {
          subject_type: subject.type,
          subject_id: subject.id,
          since: instantArg(options.since) ?? null,
          max_rows: options.limit ?? 100,
        },
        readList,
      ),
  };
}
