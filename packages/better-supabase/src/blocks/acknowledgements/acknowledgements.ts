import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { temporal } from "../../core/temporal-required.ts";
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

/** A record a version belongs to. */
export interface AcknowledgementRecord {
  readonly type: string;
  readonly id: string;
}

/** Who an acknowledgement is assigned to. */
export interface AcknowledgementPrincipal {
  readonly type: "user" | "team" | "role";
  readonly id: string;
}

/** One acknowledgement. */
export interface Acknowledgement {
  readonly id: string;
  readonly organizationId: string;
  readonly subject: AcknowledgementRecord;
  readonly versionId: string;
  readonly userId: string;
  readonly method: "click" | "signature";
  readonly signatureId?: string;
  readonly acknowledgedAt: Temporal.Instant;
}

/** One assignment. */
export interface AcknowledgementAssignment {
  readonly id: string;
  readonly organizationId: string;
  readonly subject: AcknowledgementRecord;
  readonly principal: AcknowledgementPrincipal;
  readonly dueInDays?: number;
  readonly dueOn?: Temporal.PlainDate;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
}

/** The acknowledgement state of a record's current version. */
export interface AcknowledgementStatus {
  readonly versionId: string | null;
  readonly required: number;
  readonly acknowledged: number;
  readonly pending: readonly {
    readonly userId: string;
    readonly dueOn?: Temporal.PlainDate;
    readonly overdue: boolean;
  }[];
}

/** One pending acknowledgement in the caller's inbox. */
export interface MyAcknowledgement {
  readonly subject: AcknowledgementRecord;
  readonly assignmentId: string;
  readonly versionId: string | null;
  readonly dueOn?: Temporal.PlainDate;
  readonly overdue: boolean;
  readonly acknowledgedAt?: Temporal.Instant;
}

/** The options `assign` takes. */
export interface AssignAcknowledgementOptions {
  readonly dueInDays?: number;
}

/** The options `acknowledge` takes. */
export interface AcknowledgeOptions {
  readonly versionId?: string;
  readonly signatureId?: string;
}

/** The options `mine` takes. */
export interface MyAcknowledgementsOptions {
  readonly pendingOnly?: boolean;
}

/** The acknowledgements client. */
export interface Acknowledgements {
  assign(
    organizationId: string,
    record: AcknowledgementRecord,
    principal: AcknowledgementPrincipal,
    options?: AssignAcknowledgementOptions,
  ): AsyncResult<AcknowledgementAssignment>;
  unassign(assignmentId: string): AsyncResult<AcknowledgementAssignment>;
  assignments(
    record: AcknowledgementRecord,
  ): AsyncResult<readonly AcknowledgementAssignment[]>;
  acknowledge(
    record: AcknowledgementRecord,
    options?: AcknowledgeOptions,
  ): AsyncResult<Acknowledgement>;
  mine(
    organizationId: string,
    options?: MyAcknowledgementsOptions,
  ): AsyncResult<readonly MyAcknowledgement[]>;
  status(record: AcknowledgementRecord): AsyncResult<AcknowledgementStatus>;
  of(
    record: AcknowledgementRecord,
    versionId?: string,
  ): AsyncResult<readonly Acknowledgement[]>;
  notifyDue(): AsyncResult<number>;
}

/** `createAcknowledgements` options. */
export interface AcknowledgementsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly fields?: S;
  readonly hooks?: NoInfer<BlockHooks<Acknowledgements>>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

const methodOf = (value: unknown, fn: string): "click" | "signature" =>
  enumOrThrow(value, ["click", "signature"], fn);

const principalTypeOf = (
  value: unknown,
  fn: string,
): "user" | "team" | "role" =>
  enumOrThrow(value, ["user", "team", "role"], fn);

const assignmentOf = (value: unknown, fn: string): AcknowledgementAssignment => {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    subject: {
      type: textOf(row["subjectType"]),
      id: textOf(row["subjectId"]),
    },
    principal: {
      type: principalTypeOf(row["principalType"], fn),
      id: textOf(row["principalId"]),
    },
    ...(row["dueInDays"] === null || row["dueInDays"] === undefined
      ? {}
      : { dueInDays: Number(row["dueInDays"]) }),
    ...(row["dueOn"] === null || row["dueOn"] === undefined
      ? {}
      : { dueOn: temporal().PlainDate.from(textOf(row["dueOn"])) }),
    ...(row["createdBy"] === null || row["createdBy"] === undefined
      ? {}
      : { createdBy: textOf(row["createdBy"]) }),
    createdAt: requiredInstant(row["createdAt"], fn),
  };
};

const acknowledgementOf = (value: unknown, fn: string): Acknowledgement => {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    subject: {
      type: textOf(row["subjectType"]),
      id: textOf(row["subjectId"]),
    },
    versionId: textOf(row["versionId"]),
    userId: textOf(row["userId"]),
    method: methodOf(row["method"], fn),
    ...(row["signatureId"] === null || row["signatureId"] === undefined
      ? {}
      : { signatureId: textOf(row["signatureId"]) }),
    acknowledgedAt: requiredInstant(row["acknowledgedAt"], fn),
  };
};

const statusOf = (value: unknown, fn: string): AcknowledgementStatus => {
  const row = recordOf(value, fn);

  return {
    versionId: optionalText(row["versionId"]) ?? null,
    required: Number(row["required"]),
    acknowledged: Number(row["acknowledged"]),
    pending: recordsOf(row["pending"], `${fn}.pending`).map((item) => ({
      userId: textOf(item["userId"]),
      ...(item["dueOn"] === null || item["dueOn"] === undefined
        ? {}
        : { dueOn: temporal().PlainDate.from(textOf(item["dueOn"])) }),
      overdue: item["overdue"] === true,
    })),
  };
};

const mineOf = (value: unknown, fn: string): MyAcknowledgement => {
  const row = recordOf(value, fn);

  return {
    subject: {
      type: textOf(row["subjectType"]),
      id: textOf(row["subjectId"]),
    },
    assignmentId: textOf(row["assignmentId"]),
    versionId: optionalText(row["versionId"]) ?? null,
    ...(row["dueOn"] === null || row["dueOn"] === undefined
      ? {}
      : { dueOn: temporal().PlainDate.from(textOf(row["dueOn"])) }),
    overdue: row["overdue"] === true,
    ...(() => {
      const acknowledgedAt = optionalInstant(row["acknowledgedAt"]);

      return acknowledgedAt === undefined ? {} : { acknowledgedAt };
    })(),
  };
};

/** The `acknowledgements` SQL module as typed calls. */
export function createAcknowledgements<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: AcknowledgementsOptions<S>): Acknowledgements {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  blockFields(options.fields, "acknowledgement fields");

  const readAssignment = (
    value: unknown,
    fn: string,
  ): AcknowledgementAssignment => assignmentOf(value, fn);

  const recordArgs = (record: AcknowledgementRecord) => ({
    subject_type: record.type,
    subject_id: record.id,
  });

  const client: Acknowledgements = {
    assign: (organizationId, record, principal, input) =>
      call(
        "assign_acknowledgement",
        {
          tenant: organizationId,
          ...recordArgs(record),
          principal_type: principal.type,
          principal_id: principal.id,
          due_in_days: input?.dueInDays ?? null,
        },
        (value) => readAssignment(value, "assign_acknowledgement"),
      ),
    unassign: (assignmentId) =>
      call("unassign_acknowledgement", { assignment_id: assignmentId }, (value) =>
        readAssignment(value, "unassign_acknowledgement"),
      ),
    assignments: (record) =>
      call(
        "list_acknowledgement_assignments",
        recordArgs(record),
        (value) =>
          recordsOf(value, "list_acknowledgement_assignments").map((row) =>
            readAssignment(row, "list_acknowledgement_assignments"),
          ),
      ),
    acknowledge: (record, input) =>
      call(
        "acknowledge",
        {
          ...recordArgs(record),
          version_id: input?.versionId ?? null,
          signature_id: input?.signatureId ?? null,
        },
        (value) => acknowledgementOf(value, "acknowledge"),
      ),
    mine: (organizationId, input) =>
      call(
        "list_my_acknowledgements",
        {
          tenant: organizationId,
          pending_only: input?.pendingOnly ?? true,
        },
        (value) =>
          recordsOf(value, "list_my_acknowledgements").map((row) =>
            mineOf(row, "list_my_acknowledgements"),
          ),
      ),
    status: (record) =>
      call("acknowledgement_status", recordArgs(record), (value) =>
        statusOf(value, "acknowledgement_status"),
      ),
    of: (record, versionId) =>
      call(
        "acknowledgements_of",
        { ...recordArgs(record), version_id: versionId ?? null },
        (value) =>
          recordsOf(value, "acknowledgements_of").map((row) =>
            acknowledgementOf(row, "acknowledgements_of"),
          ),
      ),
    notifyDue: () =>
      call("notify_due_acknowledgements", {}, Number),
  };

  return withBlockHooks(client, options.hooks, {
    block: "acknowledgements",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
