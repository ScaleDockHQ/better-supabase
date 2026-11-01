import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";

export interface QualificationsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /**
   * A Standard Schema for the holding's extra columns
   * (`blocks.qualifications.options.extraColumns`), keyed by database name. It
   * types and parses them on reads, and validates them on `grant`.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Qualifications<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

/** Who holds a qualification: a member, a company (contacts) or an asset. */
export type QualificationHolderType = "member" | "company" | "asset";

/**
 * Who a requirement applies to: a role, a team, a job title, an asset kind, a
 * segment, or one holder by id.
 */
export type QualificationTargetType =
  | "role"
  | "team"
  | "job_title"
  | "asset_kind"
  | "segment"
  | "holder";

/**
 * `valid`: held and not expiring. `expiring`: expires inside the renewal
 * window. `expired`: past its expiry. `revoked`: withdrawn.
 */
export type QualificationStatus = "valid" | "expiring" | "expired" | "revoked";

/** `missing`: never held, or only revoked holdings. */
export type QualificationGapStatus = "missing" | "expired" | "expiring";

/** How a holding was granted. */
export type QualificationSource = "manual" | "course" | "import";

/** A kind of qualification: a licence, a certification or a skill. */
export interface QualificationType {
  readonly id: string;
  readonly organizationId: string;
  readonly key: string;
  readonly name: string;
  readonly description?: string;
  readonly holderTypes: readonly QualificationHolderType[];
  /** Missing: the qualification never expires. */
  readonly validForMonths?: number;
  readonly evidenceRequired: boolean;
  /** Completing this course (courses block) grants the qualification. */
  readonly courseId?: string;
  readonly archivedAt?: Temporal.Instant;
  readonly createdAt?: Temporal.Instant;
  readonly updatedAt?: Temporal.Instant;
}

export interface QualificationTypeInput {
  /** Saving a key again updates that type and restores it if archived. */
  readonly key: string;
  readonly name: string;
  readonly holderTypes: readonly QualificationHolderType[];
  readonly validForMonths?: number;
  /** Default `false`. Grants then need an attachment or a note. */
  readonly evidenceRequired?: boolean;
  readonly courseId?: string;
  readonly description?: string;
  /** Changes this type, key included. */
  readonly typeId?: string;
}

/** Who has to hold a qualification type. */
export interface QualificationRequirement {
  readonly id: string;
  readonly organizationId: string;
  readonly qualificationTypeId: string;
  readonly targetType: QualificationTargetType;
  /** The role name, team id, job title, asset kind, segment id or holder id. */
  readonly targetValue: string;
  readonly createdAt?: Temporal.Instant;
}

/** One holding of a qualification. `F` types the extra columns. */
export interface Qualification<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly qualificationTypeId: string;
  readonly typeKey: string;
  readonly typeName: string;
  readonly holderType: QualificationHolderType;
  readonly holderId: string;
  readonly grantedOn: Temporal.PlainDate;
  readonly expiresOn?: Temporal.PlainDate;
  readonly revokedAt?: Temporal.Instant;
  readonly revokeReason?: string;
  readonly evidenceAttachmentId?: string;
  readonly evidenceNote?: string;
  readonly source: QualificationSource;
  /** The course certificate id for `course` holdings. */
  readonly sourceId?: string;
  readonly grantedBy?: string;
  readonly status: QualificationStatus;
  readonly createdAt?: Temporal.Instant;
  readonly updatedAt?: Temporal.Instant;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

export interface QualificationGrantInput<
  F extends object = Record<never, never>,
> {
  readonly typeKey: string;
  readonly holderType: QualificationHolderType;
  readonly holderId: string;
  /** Default: today. The expiry counts `validForMonths` from it. */
  readonly grantedOn?: Temporal.PlainDate;
  /** An attachment (attachments block). */
  readonly evidenceAttachmentId?: string;
  readonly evidenceNote?: string;
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
}

/** A required qualification a holder lacks or is about to lose. */
export interface QualificationGap {
  readonly holderType: QualificationHolderType;
  readonly holderId: string;
  /** The member's name or email, the company's or the asset's name. */
  readonly holderTitle: string;
  readonly typeKey: string;
  readonly typeName: string;
  readonly status: QualificationGapStatus;
  /** The latest expiry, for `expired` and `expiring` gaps. */
  readonly expiresOn?: Temporal.PlainDate;
}

export interface QualificationGapOptions {
  /** Default: `member`. */
  readonly holderType?: QualificationHolderType;
  /** One holder; a member may read their own gaps without `qualifications.read`. */
  readonly holderId?: string;
  /** Members of one team (teams block). */
  readonly teamId?: string;
  readonly typeKey?: string;
  readonly status?: QualificationGapStatus;
}

export interface QualifiedHoldersOptions {
  /** Default: `member`. */
  readonly holderType?: QualificationHolderType;
  /** Default: today. */
  readonly on?: Temporal.PlainDate;
}

export interface Qualifications<F extends object = Record<never, never>> {
  /** Needs `qualifications.manage`. */
  saveType(input: {
    organizationId: string;
    input: QualificationTypeInput;
  }): AsyncResult<QualificationType>;
  /** Needs `qualifications.manage`. Holdings stay. */
  archiveType(typeId: string): AsyncResult<QualificationType>;
  /** By name. */
  types(
    input: { organizationId: string } & { readonly includeArchived?: boolean },
  ): AsyncResult<readonly QualificationType[]>;
  /** Needs `qualifications.manage`. Adding the same target twice keeps one. */
  addRequirement(input: {
    typeId: string;
    targetType: QualificationTargetType;
    targetValue: string;
  }): AsyncResult<QualificationRequirement>;
  /** Needs `qualifications.manage`. */
  removeRequirement(
    requirementId: string,
  ): AsyncResult<QualificationRequirement>;
  requirements(
    typeId: string,
  ): AsyncResult<readonly QualificationRequirement[]>;
  /** Needs `qualifications.grant`. */
  grant(input: {
    organizationId: string;
    input: QualificationGrantInput<F>;
  }): AsyncResult<Qualification<F>>;
  /** Needs `qualifications.grant`. Revoking twice keeps the first revocation. */
  revoke(input: {
    qualificationId: string;
    reason?: string | undefined;
  }): AsyncResult<Qualification<F>>;
  /** Every holding of one holder, the newest grant first. */
  of(input: {
    holderType: QualificationHolderType;
    holderId: string;
  }): AsyncResult<readonly Qualification<F>[]>;
  /** The required qualifications holders lack, have let lapse or are about to. */
  gaps(
    input: { organizationId: string } & QualificationGapOptions,
  ): AsyncResult<readonly QualificationGap[]>;
  /** The ids of the holders with a valid holding of `typeKey` on a day. */
  qualifiedHolders(
    input: {
      organizationId: string;
      typeKey: string;
    } & QualifiedHoldersOptions,
  ): AsyncResult<readonly string[]>;
  /**
   * Reports each holding once when it starts expiring and once when it expires;
   * returns how many. Service role only; run it daily.
   */
  notifyExpiring(): AsyncResult<number>;
}

const HOLDER_TYPES: readonly QualificationHolderType[] = [
  "member",
  "company",
  "asset",
];

const TARGET_TYPES: readonly QualificationTargetType[] = [
  "role",
  "team",
  "job_title",
  "asset_kind",
  "segment",
  "holder",
];

const STATUSES: readonly QualificationStatus[] = [
  "valid",
  "expiring",
  "expired",
  "revoked",
];

const GAP_STATUSES: readonly QualificationGapStatus[] = [
  "missing",
  "expired",
  "expiring",
];

const SOURCES: readonly QualificationSource[] = ["manual", "course", "import"];

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

const optionalDate = (value: unknown): Temporal.PlainDate | undefined =>
  typeof value === "string" && value !== ""
    ? temporal().PlainDate.from(value)
    : undefined;

const dateOf = (value: unknown): Temporal.PlainDate =>
  temporal().PlainDate.from(textOf(value));

const numberOf = (value: unknown): number =>
  typeof value === "number" ? value : Number(value ?? 0);

const optionalNumber = (value: unknown): number | undefined =>
  value === null || value === undefined ? undefined : numberOf(value);

function typeOf(value: unknown, fn: string): QualificationType {
  const row = recordOf(value, fn);
  const holders = Array.isArray(row["holderTypes"]) ? row["holderTypes"] : [];

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    holderTypes: holders.map((holder) =>
      enumOrThrow(holder, HOLDER_TYPES, "holder type"),
    ),
    evidenceRequired: row["evidenceRequired"] === true,
    ...optional("description", optionalText(row["description"])),
    ...optional("validForMonths", optionalNumber(row["validForMonths"])),
    ...optional("courseId", optionalText(row["courseId"])),
    ...optional("archivedAt", optionalInstant(row["archivedAt"])),
    ...optional("createdAt", optionalInstant(row["createdAt"])),
    ...optional("updatedAt", optionalInstant(row["updatedAt"])),
  };
}

function requirementOf(value: unknown, fn: string): QualificationRequirement {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    qualificationTypeId: textOf(row["qualificationTypeId"]),
    targetType: enumOrThrow(row["targetType"], TARGET_TYPES, "target type"),
    targetValue: textOf(row["targetValue"]),
    ...optional("createdAt", optionalInstant(row["createdAt"])),
  };
}

function holdingOf(value: unknown, fn: string): Qualification {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    qualificationTypeId: textOf(row["qualificationTypeId"]),
    typeKey: textOf(row["typeKey"]),
    typeName: textOf(row["typeName"]),
    holderType: enumOrThrow(row["holderType"], HOLDER_TYPES, "holder type"),
    holderId: textOf(row["holderId"]),
    grantedOn: dateOf(row["grantedOn"]),
    source: enumOrThrow(row["source"], SOURCES, "qualification source"),
    status: enumOrThrow(row["status"], STATUSES, "qualification status"),
    ...optional("expiresOn", optionalDate(row["expiresOn"])),
    ...optional("revokedAt", optionalInstant(row["revokedAt"])),
    ...optional("revokeReason", optionalText(row["revokeReason"])),
    ...optional(
      "evidenceAttachmentId",
      optionalText(row["evidenceAttachmentId"]),
    ),
    ...optional("evidenceNote", optionalText(row["evidenceNote"])),
    ...optional("sourceId", optionalText(row["sourceId"])),
    ...optional("grantedBy", optionalText(row["grantedBy"])),
    ...optional("createdAt", optionalInstant(row["createdAt"])),
    ...optional("updatedAt", optionalInstant(row["updatedAt"])),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
  };
}

function gapOf(value: unknown, fn: string): QualificationGap {
  const row = recordOf(value, fn);

  return {
    holderType: enumOrThrow(row["holderType"], HOLDER_TYPES, "holder type"),
    holderId: textOf(row["holderId"]),
    holderTitle: textOf(row["holderTitle"]),
    typeKey: textOf(row["typeKey"]),
    typeName: textOf(row["typeName"]),
    status: enumOrThrow(row["status"], GAP_STATUSES, "gap status"),
    ...optional("expiresOn", optionalDate(row["expiresOn"])),
  };
}

const many =
  <T>(fn: string, of: (value: unknown, fn: string) => T) =>
  (value: unknown): readonly T[] =>
    recordsOf(value, fn).map((row) => of(row, fn));

const idsOf = (value: unknown): readonly string[] =>
  Array.isArray(value) ? value.map(textOf) : [];

/** The `qualifications` SQL module as typed calls. */
export function createQualifications<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: QualificationsOptions<S>): Qualifications<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const fields: BlockFields<F> = blockFields(
    options.fields,
    "qualification fields",
  );

  const holding = (fn: string) => (value: unknown) => holdingOf(value, fn);

  const requirement = (fn: string) => (value: unknown) =>
    requirementOf(value, fn);

  const client: Qualifications<F> = {
    saveType: ({ organizationId, input }) =>
      call(
        "save_qualification_type",
        {
          tenant: organizationId,
          key: input.key,
          name: input.name,
          holder_types: input.holderTypes,
          valid_for_months: input.validForMonths ?? null,
          evidence_required: input.evidenceRequired ?? false,
          course_id: input.courseId ?? null,
          description: input.description ?? null,
          type_id: input.typeId ?? null,
        },
        (value) => typeOf(value, "save_qualification_type"),
      ),
    archiveType: (typeId) =>
      call("archive_qualification_type", { type_id: typeId }, (value) =>
        typeOf(value, "archive_qualification_type"),
      ),
    types: ({ organizationId, ...list }) =>
      call(
        "list_qualification_types",
        {
          tenant: organizationId,
          include_archived: list.includeArchived ?? false,
        },
        many("list_qualification_types", typeOf),
      ),
    addRequirement: ({ typeId, targetType, targetValue }) =>
      call(
        "add_qualification_requirement",
        { type_id: typeId, target_type: targetType, target_value: targetValue },
        requirement("add_qualification_requirement"),
      ),
    removeRequirement: (requirementId) =>
      call(
        "remove_qualification_requirement",
        { requirement_id: requirementId },
        requirement("remove_qualification_requirement"),
      ),
    requirements: (typeId) =>
      call(
        "list_qualification_requirements",
        { type_id: typeId },
        many("list_qualification_requirements", requirementOf),
      ),
    grant: ({ organizationId, input }) =>
      fields
        .args(input.fields)
        .andThen((checked) =>
          call(
            "grant_qualification",
            {
              tenant: organizationId,
              type_key: input.typeKey,
              holder_type: input.holderType,
              holder_id: input.holderId,
              ...optional("granted_on", input.grantedOn?.toString()),
              evidence_attachment_id: input.evidenceAttachmentId ?? null,
              evidence_note: input.evidenceNote ?? null,
              ...(checked === undefined ? {} : { fields: checked }),
            },
            holding("grant_qualification"),
          ).andThen(fields.row),
        ),
    revoke: ({ qualificationId, reason }) =>
      call(
        "revoke_qualification",
        { qualification_id: qualificationId, reason: reason ?? null },
        holding("revoke_qualification"),
      ).andThen(fields.row),
    of: ({ holderType, holderId }) =>
      call(
        "qualifications_of",
        { holder_type: holderType, holder_id: holderId },
        many("qualifications_of", holdingOf),
      ).andThen(fields.rows),
    gaps: ({ organizationId, ...list }) =>
      call(
        "qualification_gaps",
        {
          tenant: organizationId,
          holder_type: list.holderType ?? "member",
          filters: {
            ...optional("holderId", list.holderId),
            ...optional("teamId", list.teamId),
            ...optional("typeKey", list.typeKey),
            ...optional("status", list.status),
          },
        },
        many("qualification_gaps", gapOf),
      ),
    qualifiedHolders: ({ organizationId, typeKey, ...list }) =>
      call(
        "qualified_holders",
        {
          tenant: organizationId,
          type_key: typeKey,
          holder_type: list.holderType ?? "member",
          ...optional("on_date", list.on?.toString()),
        },
        idsOf,
      ),
    notifyExpiring: () => call("notify_expiring_qualifications", {}, numberOf),
  };

  return withBlockHooks(client, options.hooks, {
    block: "qualifications",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
