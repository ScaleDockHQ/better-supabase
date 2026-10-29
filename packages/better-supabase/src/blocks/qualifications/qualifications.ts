import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  applyTemporal,
  blockCall,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  stringsOf,
  textOf,
} from "../shared.ts";

/** A qualification type. */
export interface QualificationType {
  readonly id: string;
  readonly organizationId: string;
  readonly key: string;
  readonly name: string;
  readonly description?: string;
  readonly holderTypes: readonly string[];
  readonly validForMonths?: number;
  readonly evidenceRequired: boolean;
  readonly archivedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** The input of `saveType`. */
export interface QualificationTypeInput {
  readonly key: string;
  readonly name: string;
  readonly description?: string;
  readonly holderTypes?: readonly string[];
  readonly validForMonths?: number;
  readonly evidenceRequired?: boolean;
}

/** One holding. */
export interface Qualification {
  readonly id: string;
  readonly organizationId: string;
  readonly typeId: string;
  readonly holderType: string;
  readonly holderId: string;
  readonly grantedOn: Temporal.PlainDate;
  readonly expiresOn?: Temporal.PlainDate;
  readonly revokedAt?: Temporal.Instant;
  readonly revokeReason?: string;
  readonly evidenceNote?: string;
  readonly source: "manual" | "course" | "import";
  readonly grantedBy?: string;
  readonly status?: "valid" | "expiring" | "expired" | "revoked";
}

/** A requirement. */
export interface QualificationRequirement {
  readonly id: string;
  readonly typeId: string;
  readonly targetType: string;
  readonly targetValue: string;
}

/** A gap row. */
export interface QualificationGap {
  readonly holderType: string;
  readonly holderId: string;
  readonly typeKey: string;
  readonly typeName: string;
  readonly status: "missing" | "expired" | "expiring";
  readonly expiresOn?: Temporal.PlainDate;
}

/** The input of `grant`. */
export interface QualificationGrantInput {
  readonly typeKey: string;
  readonly holderType: string;
  readonly holderId: string;
  readonly grantedOn?: Temporal.PlainDate;
  readonly evidenceNote?: string;
  readonly source?: "manual" | "course" | "import";
}

/** The qualifications client. */
export interface Qualifications {
  saveType(
    organizationId: string,
    input: QualificationTypeInput,
  ): AsyncResult<QualificationType>;
  archiveType(typeId: string): AsyncResult<QualificationType>;
  types(organizationId: string): AsyncResult<readonly QualificationType[]>;
  addRequirement(
    typeId: string,
    targetType: string,
    targetValue: string,
  ): AsyncResult<QualificationRequirement>;
  removeRequirement(requirementId: string): AsyncResult<boolean>;
  requirements(
    typeId: string,
  ): AsyncResult<readonly QualificationRequirement[]>;
  grant(
    organizationId: string,
    input: QualificationGrantInput,
  ): AsyncResult<Qualification>;
  revoke(qualificationId: string, reason: string): AsyncResult<Qualification>;
  of(
    holderType: string,
    holderId: string,
  ): AsyncResult<readonly Qualification[]>;
  gaps(
    organizationId: string,
    holderType?: string,
  ): AsyncResult<readonly QualificationGap[]>;
  notifyExpiring(): AsyncResult<number>;
}

/** `createQualifications` options. */
export interface QualificationsOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly hooks?: NoInfer<BlockHooks<Qualifications>>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

const typeOf = (value: unknown, fn: string): QualificationType => {
  const row = recordOf(value, fn);
  const archivedAt = optionalInstant(row["archivedAt"]);
  const description = optionalText(row["description"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    ...(description === undefined ? {} : { description }),
    holderTypes: stringsOf(row["holderTypes"]),
    ...(row["validForMonths"] === null || row["validForMonths"] === undefined
      ? {}
      : { validForMonths: Number(row["validForMonths"]) }),
    evidenceRequired: row["evidenceRequired"] === true,
    ...(archivedAt === undefined ? {} : { archivedAt }),
    createdAt: requiredInstant(row["createdAt"], fn),
    updatedAt: requiredInstant(row["updatedAt"], fn),
  };
};

const qualificationOf = (value: unknown, fn: string): Qualification => {
  const row = recordOf(value, fn);
  const revokedAt = optionalInstant(row["revokedAt"]);
  const revokeReason = optionalText(row["revokeReason"]);
  const evidenceNote = optionalText(row["evidenceNote"]);
  const grantedBy = optionalText(row["grantedBy"]);
  const status = optionalText(row["status"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    typeId: textOf(row["typeId"]),
    holderType: textOf(row["holderType"]),
    holderId: textOf(row["holderId"]),
    grantedOn: temporal().PlainDate.from(textOf(row["grantedOn"])),
    ...(row["expiresOn"] === null || row["expiresOn"] === undefined
      ? {}
      : { expiresOn: temporal().PlainDate.from(textOf(row["expiresOn"])) }),
    ...(revokedAt === undefined ? {} : { revokedAt }),
    ...(revokeReason === undefined ? {} : { revokeReason }),
    ...(evidenceNote === undefined ? {} : { evidenceNote }),
    // SAFETY: qualifications.source has a check constraint on these three values.
    source: textOf(row["source"]) as Qualification["source"],
    ...(grantedBy === undefined ? {} : { grantedBy }),
    // SAFETY: qualifications_of computes one of these four statuses.
    ...(status === undefined
      ? {}
      : { status: status as NonNullable<Qualification["status"]> }),
  };
};

const requirementOf = (
  value: unknown,
  fn: string,
): QualificationRequirement => {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    typeId: textOf(row["typeId"]),
    targetType: textOf(row["targetType"]),
    targetValue: textOf(row["targetValue"]),
  };
};

const gapOf = (value: unknown, fn: string): QualificationGap => {
  const row = recordOf(value, fn);

  return {
    holderType: textOf(row["holderType"]),
    holderId: textOf(row["holderId"]),
    typeKey: textOf(row["typeKey"]),
    typeName: textOf(row["typeName"]),
    // SAFETY: qualification_gaps computes one of these three statuses.
    status: textOf(row["status"]) as QualificationGap["status"],
    ...(row["expiresOn"] === null || row["expiresOn"] === undefined
      ? {}
      : { expiresOn: temporal().PlainDate.from(textOf(row["expiresOn"])) }),
  };
};

/** The `qualifications` SQL module as typed calls. */
export function createQualifications(
  options: QualificationsOptions,
): Qualifications {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  blockFields(undefined, "qualification fields");

  const client: Qualifications = {
    saveType: (organizationId, input) =>
      call(
        "save_qualification_type",
        {
          tenant: organizationId,
          key: input.key,
          name: input.name,
          holder_types: input.holderTypes ?? ["member"],
          valid_for_months: input.validForMonths ?? null,
          evidence_required: input.evidenceRequired ?? false,
          description: input.description ?? null,
          type_id: null,
        },
        (value) => typeOf(value, "save_qualification_type"),
      ),
    archiveType: (typeId) =>
      call("archive_qualification_type", { type_id: typeId }, (value) =>
        typeOf(value, "archive_qualification_type"),
      ),
    types: (organizationId) =>
      call(
        "list_qualification_types",
        { tenant: organizationId },
        (value) =>
          recordsOf(value, "list_qualification_types").map((row) =>
            typeOf(row, "list_qualification_types"),
          ),
      ),
    addRequirement: (typeId, targetType, targetValue) =>
      call(
        "add_qualification_requirement",
        { type_id: typeId, target_type: targetType, target_value: targetValue },
        (value) => requirementOf(value, "add_qualification_requirement"),
      ),
    removeRequirement: (requirementId) =>
      call(
        "remove_qualification_requirement",
        { requirement_id: requirementId },
        (value) => value === true,
      ),
    requirements: (typeId) =>
      call(
        "list_qualification_requirements",
        { type_id: typeId },
        (value) =>
          recordsOf(value, "list_qualification_requirements").map((row) =>
            requirementOf(row, "list_qualification_requirements"),
          ),
      ),
    grant: (organizationId, input) =>
      call(
        "grant_qualification",
        {
          tenant: organizationId,
          type_key: input.typeKey,
          holder_type: input.holderType,
          holder_id: input.holderId,
          granted_on: input.grantedOn?.toString() ?? null,
          evidence_note: input.evidenceNote ?? null,
          source: input.source ?? "manual",
        },
        (value) => qualificationOf(value, "grant_qualification"),
      ),
    revoke: (qualificationId, reason) =>
      call(
        "revoke_qualification",
        { qualification_id: qualificationId, reason },
        (value) => qualificationOf(value, "revoke_qualification"),
      ),
    of: (holderType, holderId) =>
      call(
        "qualifications_of",
        { holder_type: holderType, holder_id: holderId },
        (value) =>
          recordsOf(value, "qualifications_of").map((row) =>
            qualificationOf(row, "qualifications_of"),
          ),
      ),
    gaps: (organizationId, holderType) =>
      call(
        "qualification_gaps",
        { tenant: organizationId, holder_type: holderType ?? "member" },
        (value) =>
          recordsOf(value, "qualification_gaps").map((row) =>
            gapOf(row, "qualification_gaps"),
          ),
      ),
    notifyExpiring: () =>
      call("notify_expiring_qualifications", {}, Number),
  };

  return withBlockHooks(client, options.hooks, {
    block: "qualifications",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
