import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockOptions, RecordRef } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { plainDate } from "../sales-shared.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** Options for {@link createAcknowledgements}. */
export interface AcknowledgementsOptions extends BlockOptions {
  /** `before` and `after` hooks per method (ADR 0015). */
  readonly hooks?: NoInfer<BlockHooks<Acknowledgements>>;
  /** Receives an error a hook throws. */
  readonly logger?: Logger;
}

/** Who an assignment asks to acknowledge a record. */
export type AcknowledgementPrincipalType = "user" | "team" | "role";

/** A member, a team (its id) or a role (its name). */
export interface AcknowledgementPrincipal {
  readonly type: AcknowledgementPrincipalType;
  readonly id: string;
}

/** How a member acknowledged: a click, or a completed signature request. */
export type AcknowledgementMethod = "click" | "signature";

/** A request that a member, team or role acknowledges a record. */
export interface AcknowledgementAssignment {
  readonly id: string;
  readonly organizationId: string;
  readonly record: RecordRef;
  readonly principal: AcknowledgementPrincipal;
  /**
   * Days after a version is frozen that an acknowledgement of it is due;
   * `undefined` when it has no due date.
   */
  readonly dueInDays?: number;
  readonly createdBy?: string;
  readonly createdAt?: Temporal.Instant;
}

/** One member's acknowledgement of one version of a record. */
export interface Acknowledgement {
  readonly id: string;
  readonly organizationId: string;
  readonly record: RecordRef;
  readonly versionId: string;
  readonly userId: string;
  readonly method?: AcknowledgementMethod;
  readonly signatureId?: string;
  readonly acknowledgedAt: Temporal.Instant;
}

/** A record the caller is asked to acknowledge, with its current version. */
export interface MyAcknowledgement {
  readonly organizationId: string;
  readonly record: RecordRef;
  /** The record's title, when the subject type declares a title column. */
  readonly title?: string;
  readonly versionId: string;
  readonly dueOn?: Temporal.PlainDate;
  readonly overdue: boolean;
  /** Set once the caller acknowledged the current version. */
  readonly acknowledgedAt?: Temporal.Instant;
}

/** A member who still has to acknowledge a record's current version. */
export interface PendingAcknowledgement {
  readonly userId: string;
  readonly dueOn?: Temporal.PlainDate;
  readonly overdue: boolean;
}

/** Who acknowledged a record's current version, and who still has to. */
export interface AcknowledgementStatus {
  /** `undefined` while the record has no frozen version. */
  readonly versionId?: string;
  /** The members the assignments cover. */
  readonly required: number;
  readonly acknowledged: number;
  readonly pending: readonly PendingAcknowledgement[];
}

/** Options for {@link Acknowledgements.assign}. */
export interface AssignAcknowledgementOptions {
  /** Days after a version is frozen that its acknowledgement is due. */
  readonly dueInDays?: number;
}

/** Options for {@link Acknowledgements.acknowledge}. */
export interface AcknowledgeOptions {
  /**
   * The version the member read. Defaults to the current one; another version
   * fails with `ACKNOWLEDGEMENT_VERSION_STALE`.
   */
  readonly versionId?: string;
  /**
   * A completed `signatures` request on the same version, which the member
   * signed. Records the acknowledgement with the `signature` method.
   */
  readonly signatureId?: string;
}

/** Options for {@link Acknowledgements.mine}. */
export interface MyAcknowledgementsOptions {
  /** Only the records the caller still has to acknowledge. Default `true`. */
  readonly pendingOnly?: boolean;
}

/**
 * Read-and-understood acknowledgements of any versioned record: who has to
 * acknowledge it, who did, and reminders for who is overdue.
 */
export interface Acknowledgements {
  /** Asks a member, team or role to acknowledge a record. Idempotent. */
  assign(
    organizationId: string,
    record: RecordRef,
    principal: AcknowledgementPrincipal,
    options?: AssignAcknowledgementOptions,
  ): AsyncResult<AcknowledgementAssignment>;
  /** Removes an assignment. Earlier acknowledgements stay. */
  unassign(assignmentId: string): AsyncResult<AcknowledgementAssignment>;
  /** The assignments on a record. */
  assignments(
    record: RecordRef,
  ): AsyncResult<readonly AcknowledgementAssignment[]>;
  /** Records that the caller read and understood the current version. */
  acknowledge(
    record: RecordRef,
    options?: AcknowledgeOptions,
  ): AsyncResult<Acknowledgement>;
  /** The records the caller is asked to acknowledge in an organization. */
  mine(
    organizationId: string,
    options?: MyAcknowledgementsOptions,
  ): AsyncResult<readonly MyAcknowledgement[]>;
  /** Who acknowledged the current version, and who is pending or overdue. */
  status(record: RecordRef): AsyncResult<AcknowledgementStatus>;
  /** The acknowledgements of a version, the current one by default. */
  of(
    record: RecordRef,
    versionId?: string,
  ): AsyncResult<readonly Acknowledgement[]>;
  /**
   * Notifies each overdue member once per version and emits
   * `acknowledgement.reminded`. Service only; returns the count notified.
   */
  notifyDue(): AsyncResult<number>;
}

const PRINCIPALS: readonly AcknowledgementPrincipalType[] = [
  "user",
  "team",
  "role",
];

const METHODS: readonly AcknowledgementMethod[] = ["click", "signature"];

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

const optionalCount = (value: unknown): number | undefined =>
  typeof value === "number" ? value : undefined;

const recordRef = (row: Readonly<Record<string, unknown>>): RecordRef => ({
  type: textOf(row["subjectType"]),
  id: textOf(row["subjectId"]),
});

function assignmentOf(value: unknown, fn: string): AcknowledgementAssignment {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    record: recordRef(row),
    principal: {
      type: enumOrThrow(row["principalType"], PRINCIPALS, "principal type"),
      id: textOf(row["principalId"]),
    },
    ...optional("dueInDays", optionalCount(row["dueInDays"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
    ...optional("createdAt", optionalInstant(row["createdAt"])),
  };
}

function acknowledgementOf(value: unknown, fn: string): Acknowledgement {
  const row = recordOf(value, fn);
  const method = optionalText(row["method"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    record: recordRef(row),
    versionId: textOf(row["versionId"]),
    userId: textOf(row["userId"]),
    acknowledgedAt: requiredInstant(row["acknowledgedAt"], "acknowledgedAt"),
    ...optional(
      "method",
      method === undefined
        ? undefined
        : enumOrThrow(method, METHODS, "acknowledgement method"),
    ),
    ...optional("signatureId", optionalText(row["signatureId"])),
  };
}

function myAcknowledgementOf(value: unknown, fn: string): MyAcknowledgement {
  const row = recordOf(value, fn);

  return {
    organizationId: textOf(row["organizationId"]),
    record: recordRef(row),
    versionId: textOf(row["versionId"]),
    overdue: row["overdue"] === true,
    ...optional("title", optionalText(row["subjectTitle"])),
    ...optional("dueOn", plainDate(row["dueOn"])),
    ...optional("acknowledgedAt", optionalInstant(row["acknowledgedAt"])),
  };
}

function statusOf(value: unknown, fn: string): AcknowledgementStatus {
  const row = recordOf(value, fn);

  return {
    required: optionalCount(row["required"]) ?? 0,
    acknowledged: optionalCount(row["acknowledged"]) ?? 0,
    pending: recordsOf(row["pending"], fn).map((item) => ({
      userId: textOf(item["userId"]),
      overdue: item["overdue"] === true,
      ...optional("dueOn", plainDate(item["dueOn"])),
    })),
    ...optional("versionId", optionalText(row["versionId"])),
  };
}

/**
 * Creates the `acknowledgements` client over the module's functions.
 *
 * @example
 *   ```ts
 *   const acks = createAcknowledgements({
 *     transport: sqlTransport(ctx.postgres),
 *   });
 *   await acks.assign(
 *     orgId,
 *     { type: "policy", id },
 *     { type: "role", id: "member" },
 *     { dueInDays: 14 },
 *   );
 *   await acks.acknowledge({ type: "policy", id });
 *   ```;
 */
export function createAcknowledgements(
  options: AcknowledgementsOptions,
): Acknowledgements {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );

  const client: Acknowledgements = {
    assign: (organizationId, record, principal, assign = {}) =>
      call(
        "assign_acknowledgement",
        {
          tenant: organizationId,
          subject_type: record.type,
          subject_id: record.id,
          principal_type: principal.type,
          principal_id: principal.id,
          due_in_days: assign.dueInDays ?? null,
        },
        (value) => assignmentOf(value, "assign_acknowledgement"),
      ),
    unassign: (assignmentId) =>
      call(
        "unassign_acknowledgement",
        { assignment_id: assignmentId },
        (value) => assignmentOf(value, "unassign_acknowledgement"),
      ),
    assignments: (record) =>
      call(
        "list_acknowledgement_assignments",
        { subject_type: record.type, subject_id: record.id },
        (value) =>
          recordsOf(value, "list_acknowledgement_assignments").map((row) =>
            assignmentOf(row, "list_acknowledgement_assignments"),
          ),
      ),
    acknowledge: (record, acknowledge = {}) =>
      call(
        "acknowledge",
        {
          subject_type: record.type,
          subject_id: record.id,
          version_id: acknowledge.versionId ?? null,
          signature_id: acknowledge.signatureId ?? null,
        },
        (value) => acknowledgementOf(value, "acknowledge"),
      ),
    mine: (organizationId, mine = {}) =>
      call(
        "list_my_acknowledgements",
        { tenant: organizationId, pending_only: mine.pendingOnly ?? true },
        (value) =>
          recordsOf(value, "list_my_acknowledgements").map((row) =>
            myAcknowledgementOf(row, "list_my_acknowledgements"),
          ),
      ),
    status: (record) =>
      call(
        "acknowledgement_status",
        { subject_type: record.type, subject_id: record.id },
        (value) => statusOf(value, "acknowledgement_status"),
      ),
    of: (record, versionId) =>
      call(
        "acknowledgements_of",
        {
          subject_type: record.type,
          subject_id: record.id,
          version_id: versionId ?? null,
        },
        (value) =>
          recordsOf(value, "acknowledgements_of").map((row) =>
            acknowledgementOf(row, "acknowledgements_of"),
          ),
      ),
    notifyDue: () =>
      service("notify_due_acknowledgements", {}, (value) =>
        typeof value === "number" ? value : Number(value),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "acknowledgements",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
