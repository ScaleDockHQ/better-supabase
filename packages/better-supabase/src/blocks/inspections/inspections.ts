import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  INSPECTION_MEMBER_ROLES,
  INSPECTION_PROGRAM_STATUSES,
  INSPECTION_STATUSES,
} from "../../sql/modules/inspections-values.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** Where an audit programme stands. */
export type InspectionProgramStatus =
  (typeof INSPECTION_PROGRAM_STATUSES)[number];

/** Where an inspection stands. */
export type InspectionStatus = (typeof INSPECTION_STATUSES)[number];

/** What a member does on an inspection. */
export type InspectionMemberRole = (typeof INSPECTION_MEMBER_ROLES)[number];

/** An audit programme: the inspections planned for a period. */
export interface InspectionProgram {
  readonly id: string;
  readonly organizationId: string;
  readonly name: string;
  readonly periodStart: Temporal.PlainDate;
  readonly periodEnd: Temporal.PlainDate;
  readonly ownerId?: string;
  readonly status: InspectionProgramStatus;
  readonly notes?: string;
  readonly archivedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface InspectionProgramInput {
  readonly name: string;
  readonly periodStart: Temporal.PlainDate;
  /** On or after `periodStart`. */
  readonly periodEnd: Temporal.PlainDate;
  readonly ownerId?: string | null;
  readonly notes?: string | null;
  /** Changes this programme instead of creating one. */
  readonly programId?: string;
}

/** The subject an inspection audits, such as a supplier or a site. */
export interface InspectionAuditee {
  readonly type: string;
  readonly id: string;
}

/** An inspection. `F` types the extra columns the `fields` schema describes. */
export interface Inspection<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly programId?: string;
  /** Such as `AUD-2026-001`. */
  readonly number: string;
  /** One of `options.kinds`. */
  readonly kind: string;
  readonly title: string;
  readonly scope?: string;
  readonly criteria?: string;
  readonly auditee?: InspectionAuditee;
  readonly leadId?: string;
  readonly plannedStart?: Temporal.PlainDate;
  readonly plannedEnd?: Temporal.PlainDate;
  readonly startedAt?: Temporal.Instant;
  readonly completedAt?: Temporal.Instant;
  readonly closedAt?: Temporal.Instant;
  readonly status: InspectionStatus;
  readonly checklistFormId?: string;
  readonly checklistSubmissionId?: string;
  readonly summary?: string;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  readonly fields: ExtraFields<F>;
}

export interface InspectionMember {
  readonly userId: string;
  readonly role: InspectionMemberRole;
}

/** A finding of an inspection. */
export interface InspectionFinding {
  readonly id: string;
  readonly organizationId: string;
  readonly inspectionId: string;
  /** 1, 2, 3 within the inspection. */
  readonly number: number;
  /** One of `options.findingTypes`. */
  readonly type: string;
  readonly title: string;
  readonly description?: string;
  /** The clause of the standard, such as `ISO 9001 7.5.3`. */
  readonly clause?: string;
  /** The compliance control the finding concerns. */
  readonly controlId?: string;
  readonly evidence?: string;
  /** The case raised for the finding. */
  readonly caseId?: string;
  /** Its type is one of `options.caseFindingTypes`: closing needs a case. */
  readonly needsCase: boolean;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** An inspection with its team, findings, checklist and assessed controls. */
export interface InspectionDetail<
  F extends object = Record<never, never>,
> extends Inspection<F> {
  readonly members: readonly InspectionMember[];
  readonly findings: readonly InspectionFinding[];
  readonly checklist?: {
    readonly formId: string;
    readonly submissionId?: string;
    /** The submission's status, such as `draft` or `submitted`. */
    readonly status?: string;
  };
  readonly assessedControls: readonly {
    readonly id: string;
    readonly title?: string;
  }[];
}

export interface InspectionInput<F extends object = Record<never, never>> {
  /** One of `options.kinds`. */
  readonly kind: string;
  readonly title: string;
  readonly programId?: string | null;
  readonly scope?: string | null;
  readonly criteria?: string | null;
  readonly auditee?: InspectionAuditee | null;
  readonly leadId?: string | null;
  readonly plannedStart?: Temporal.PlainDate | null;
  readonly plannedEnd?: Temporal.PlainDate | null;
  /** An open form of the organization, filled in while in progress. */
  readonly checklistFormId?: string | null;
  /** The team besides the lead. */
  readonly members?: readonly InspectionMember[];
  /** The extra columns, keyed by database name. */
  readonly fields?: Partial<F>;
}

/** What `update` changes; keys left out keep their value. */
export type InspectionChange<F extends object = Record<never, never>> = Partial<
  Omit<InspectionInput<F>, "members">
>;

export interface InspectionFindingInput {
  /** One of `options.findingTypes`. */
  readonly type: string;
  readonly title: string;
  readonly description?: string | null;
  readonly clause?: string | null;
  readonly controlId?: string | null;
  readonly evidence?: string | null;
}

export interface InspectionListOptions {
  readonly programId?: string;
  readonly kind?: string;
  readonly status?: InspectionStatus;
  readonly leadId?: string;
  /** Planned to start on or after. */
  readonly from?: Temporal.PlainDate;
  /** Planned to start on or before. */
  readonly to?: Temporal.PlainDate;
  readonly auditee?: InspectionAuditee;
  /** Matches the title, number, scope or summary. */
  readonly search?: string;
  /** 1 to 200. Default 50. */
  readonly limit?: number;
  readonly offset?: number;
}

export interface Inspections<F extends object = Record<never, never>> {
  /** Creates or changes a programme; needs `inspections.manage`. */
  saveProgram(input: InspectionProgramInput): AsyncResult<InspectionProgram>;
  approveProgram(programId: string): AsyncResult<InspectionProgram>;
  closeProgram(programId: string): AsyncResult<InspectionProgram>;
  /** The organization's programmes, the latest period first. */
  programs(): AsyncResult<readonly InspectionProgram[]>;
  /** Schedules a planned inspection; needs `inspections.manage`. */
  schedule(input: InspectionInput<F>): AsyncResult<Inspection<F>>;
  /** Changes an inspection, as its lead or with `inspections.manage`. */
  update(input: {
    inspectionId: string;
    change: InspectionChange<F>;
  }): AsyncResult<Inspection<F>>;
  /** Replaces the team; the lead stays unless `members` names a new one. */
  setMembers(input: {
    inspectionId: string;
    members: readonly InspectionMember[];
  }): AsyncResult<Inspection<F>>;
  /** Starts the fieldwork and opens a draft of the checklist form. */
  start(inspectionId: string): AsyncResult<Inspection<F>>;
  /** Saves the checklist answers; `draft: false` submits them. */
  saveChecklist(
    input: {
      inspectionId: string;
      answers: Readonly<Record<string, unknown>>;
    } & { readonly draft?: boolean },
  ): AsyncResult<{ readonly submissionId: string }>;
  /** Ends the fieldwork; the checklist must be submitted. */
  complete(input: {
    inspectionId: string;
    summary?: string | undefined;
  }): AsyncResult<Inspection<F>>;
  /**
   * Closes the inspection; fails with `INSPECTION_FINDINGS_OPEN` while a
   * finding that needs a case has none.
   */
  close(inspectionId: string): AsyncResult<Inspection<F>>;
  /** Cancels an inspection that hasn't closed; needs `inspections.manage`. */
  cancel(input: {
    inspectionId: string;
    reason?: string | undefined;
  }): AsyncResult<Inspection<F>>;
  /**
   * Tells the lead (or the auditors) of each planned or running inspection past
   * its planned end, once per planned end, and returns how many it found.
   * Service role only.
   */
  notifyOverdue(): AsyncResult<number>;
  get(inspectionId: string): AsyncResult<InspectionDetail<F>>;
  list(options?: InspectionListOptions): AsyncResult<readonly Inspection<F>[]>;
  addFinding(input: {
    inspectionId: string;
    input: InspectionFindingInput;
  }): AsyncResult<InspectionFinding>;
  updateFinding(input: {
    findingId: string;
    change: Partial<InspectionFindingInput>;
  }): AsyncResult<InspectionFinding>;
  /** Deletes a finding that has no case. */
  deleteFinding(findingId: string): AsyncResult<InspectionFinding>;
  /** Opens a case for the finding through the cases block. */
  raiseCase(
    input: { findingId: string } & {
      readonly kind?: string;
      readonly ownerId?: string;
    },
  ): AsyncResult<InspectionFinding>;
}

export interface InspectionsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockOptions {
  /**
   * A Standard Schema for the inspection's extra columns
   * (`blocks.inspections.options.extraColumns`), keyed by database name.
   */
  readonly fields?: S;
  readonly hooks?: NoInfer<BlockHooks<Inspections<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

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

const requiredDate = (value: unknown, name: string): Temporal.PlainDate => {
  const date = optionalDate(value);

  if (date === undefined) {
    throw new TypeError(`inspections: ${name} is missing`);
  }

  return date;
};

const dateArg = (
  value: Temporal.PlainDate | null | undefined,
): string | null | undefined =>
  value === undefined ? undefined : value === null ? null : value.toString();

const definedOf = (input: object): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(input).filter(([, value]) => value !== undefined),
  );

function programOf(value: unknown, fn: string): InspectionProgram {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    name: textOf(row["name"]),
    periodStart: requiredDate(row["periodStart"], "periodStart"),
    periodEnd: requiredDate(row["periodEnd"], "periodEnd"),
    status: enumOrThrow(
      row["status"],
      INSPECTION_PROGRAM_STATUSES,
      "inspection programme status",
    ),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("ownerId", optionalText(row["ownerId"])),
    ...optional("notes", optionalText(row["notes"])),
    ...optional("archivedAt", optionalInstant(row["archivedAt"])),
  };
}

function inspectionOf(value: unknown, fn: string): Inspection {
  const row = recordOf(value, fn);
  const auditee = isRecord(row["auditee"]) ? row["auditee"] : undefined;

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    number: textOf(row["number"]),
    kind: textOf(row["kind"]),
    title: textOf(row["title"]),
    status: enumOrThrow(
      row["status"],
      INSPECTION_STATUSES,
      "inspection status",
    ),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
    ...optional("programId", optionalText(row["programId"])),
    ...optional("scope", optionalText(row["scope"])),
    ...optional("criteria", optionalText(row["criteria"])),
    ...optional(
      "auditee",
      auditee === undefined
        ? undefined
        : { type: textOf(auditee["type"]), id: textOf(auditee["id"]) },
    ),
    ...optional("leadId", optionalText(row["leadId"])),
    ...optional("plannedStart", optionalDate(row["plannedStart"])),
    ...optional("plannedEnd", optionalDate(row["plannedEnd"])),
    ...optional("startedAt", optionalInstant(row["startedAt"])),
    ...optional("completedAt", optionalInstant(row["completedAt"])),
    ...optional("closedAt", optionalInstant(row["closedAt"])),
    ...optional("checklistFormId", optionalText(row["checklistFormId"])),
    ...optional(
      "checklistSubmissionId",
      optionalText(row["checklistSubmissionId"]),
    ),
    ...optional("summary", optionalText(row["summary"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
  };
}

function findingOf(value: unknown, fn: string): InspectionFinding {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    inspectionId: textOf(row["inspectionId"]),
    number: Number(row["number"]),
    type: textOf(row["type"]),
    title: textOf(row["title"]),
    needsCase: row["needsCase"] === true,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("description", optionalText(row["description"])),
    ...optional("clause", optionalText(row["clause"])),
    ...optional("controlId", optionalText(row["controlId"])),
    ...optional("evidence", optionalText(row["evidence"])),
    ...optional("caseId", optionalText(row["caseId"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
  };
}

function detailOf(value: unknown, fn: string): InspectionDetail {
  const row = recordOf(value, fn);
  const checklist = isRecord(row["checklist"]) ? row["checklist"] : undefined;

  return {
    ...inspectionOf(row, fn),
    members: recordsOf(row["members"], fn).map((member) => ({
      userId: textOf(member["userId"]),
      role: enumOrThrow(
        member["role"],
        INSPECTION_MEMBER_ROLES,
        "inspection member role",
      ),
    })),
    findings: recordsOf(row["findings"], fn).map((finding) =>
      findingOf(finding, fn),
    ),
    assessedControls: recordsOf(row["assessedControls"], fn).map((control) => ({
      id: textOf(control["id"]),
      ...optional("title", optionalText(control["title"])),
    })),
    ...optional(
      "checklist",
      checklist === undefined
        ? undefined
        : {
            formId: textOf(checklist["formId"]),
            ...optional(
              "submissionId",
              optionalText(checklist["submissionId"]),
            ),
            ...optional("status", optionalText(checklist["status"])),
          },
    ),
  };
}

/** The `schedule_inspection` and `update_inspection` input. */
function inspectionArgs(
  input: InspectionChange & { readonly members?: readonly InspectionMember[] },
  fields: unknown,
): Record<string, unknown> {
  return definedOf({
    ...input,
    plannedStart: dateArg(input.plannedStart),
    plannedEnd: dateArg(input.plannedEnd),
    fields,
  });
}

/**
 * Audits and inspections: programmes of planned inspections, each with a team,
 * a checklist form, findings and the cases nonconformities raise.
 */
export function createInspections<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: InspectionsOptions<S>): Inspections<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const fields: BlockFields<F> = blockFields(
    options.fields,
    "inspection fields",
  );

  const one = (fn: string) => (value: unknown) => inspectionOf(value, fn);
  const finding = (fn: string) => (value: unknown) => findingOf(value, fn);
  const program = (fn: string) => (value: unknown) => programOf(value, fn);

  const client: Inspections<F> = {
    saveProgram: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "save_inspection_program",
          {
            tenant: organizationId,
            name: input.name,
            period_start: input.periodStart.toString(),
            period_end: input.periodEnd.toString(),
            owner_id: input.ownerId ?? null,
            notes: input.notes ?? null,
            program_id: input.programId ?? null,
          },
          program("save_inspection_program"),
        ),
      ),
    approveProgram: (programId) =>
      call(
        "approve_inspection_program",
        { program_id: programId },
        program("approve_inspection_program"),
      ),
    closeProgram: (programId) =>
      call(
        "close_inspection_program",
        { program_id: programId },
        program("close_inspection_program"),
      ),
    programs: () =>
      tenant().andThen((organizationId) =>
        call("list_inspection_programs", { tenant: organizationId }, (value) =>
          recordsOf(value, "list_inspection_programs").map((row) =>
            programOf(row, "list_inspection_programs"),
          ),
        ),
      ),
    schedule: (input) =>
      tenant().andThen((organizationId) =>
        fields
          .args(input.fields)
          .andThen((checked) =>
            call(
              "schedule_inspection",
              { tenant: organizationId, input: inspectionArgs(input, checked) },
              one("schedule_inspection"),
            ).andThen(fields.row),
          ),
      ),
    update: ({ inspectionId, change }) =>
      fields
        .args(change.fields)
        .andThen((checked) =>
          call(
            "update_inspection",
            {
              inspection_id: inspectionId,
              changes: inspectionArgs(change, checked),
            },
            one("update_inspection"),
          ).andThen(fields.row),
        ),
    setMembers: ({ inspectionId, members }) =>
      call(
        "set_inspection_members",
        { inspection_id: inspectionId, members },
        one("set_inspection_members"),
      ).andThen(fields.row),
    start: (inspectionId) =>
      call(
        "start_inspection",
        { inspection_id: inspectionId },
        one("start_inspection"),
      ).andThen(fields.row),
    saveChecklist: ({ inspectionId, answers, ...save }) =>
      call(
        "save_inspection_checklist",
        { inspection_id: inspectionId, answers, draft: save.draft ?? true },
        (value) => ({
          submissionId: textOf(
            recordOf(value, "save_inspection_checklist")["id"],
          ),
        }),
      ),
    complete: ({ inspectionId, summary }) =>
      call(
        "complete_inspection",
        { inspection_id: inspectionId, summary: summary ?? null },
        one("complete_inspection"),
      ).andThen(fields.row),
    close: (inspectionId) =>
      call(
        "close_inspection",
        { inspection_id: inspectionId },
        one("close_inspection"),
      ).andThen(fields.row),
    cancel: ({ inspectionId, reason }) =>
      call(
        "cancel_inspection",
        { inspection_id: inspectionId, reason: reason ?? null },
        one("cancel_inspection"),
      ).andThen(fields.row),
    notifyOverdue: () =>
      call("notify_overdue_inspections", {}, (value) => Number(value ?? 0)),
    get: (inspectionId) =>
      call("get_inspection", { inspection_id: inspectionId }, (value) =>
        detailOf(value, "get_inspection"),
      ).andThen(fields.row),
    list: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_inspections",
          {
            tenant: organizationId,
            filters: definedOf({
              programId: list.programId,
              kind: list.kind,
              status: list.status,
              leadId: list.leadId,
              from: dateArg(list.from),
              to: dateArg(list.to),
              auditeeType: list.auditee?.type,
              auditeeId: list.auditee?.id,
              search: list.search,
              limit: list.limit,
              offset: list.offset,
            }),
          },
          (value) =>
            recordsOf(value, "list_inspections").map((row) =>
              inspectionOf(row, "list_inspections"),
            ),
        ).andThen(fields.rows),
      ),
    addFinding: ({ inspectionId, input }) =>
      call(
        "add_inspection_finding",
        {
          inspection_id: inspectionId,
          type: input.type,
          title: input.title,
          description: input.description ?? null,
          clause: input.clause ?? null,
          control_id: input.controlId ?? null,
          evidence: input.evidence ?? null,
        },
        finding("add_inspection_finding"),
      ),
    updateFinding: ({ findingId, change }) =>
      call(
        "update_inspection_finding",
        { finding_id: findingId, changes: definedOf(change) },
        finding("update_inspection_finding"),
      ),
    deleteFinding: (findingId) =>
      call(
        "delete_inspection_finding",
        { finding_id: findingId },
        finding("delete_inspection_finding"),
      ),
    raiseCase: ({ findingId, ...raise }) =>
      call(
        "raise_inspection_finding_case",
        {
          finding_id: findingId,
          kind: raise.kind ?? "finding",
          owner_id: raise.ownerId ?? null,
        },
        finding("raise_inspection_finding_case"),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "inspections",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
