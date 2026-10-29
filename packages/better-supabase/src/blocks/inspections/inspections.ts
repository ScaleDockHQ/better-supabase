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
  textOf,
} from "../shared.ts";

/** An inspection program. */
export interface InspectionProgram {
  readonly id: string;
  readonly organizationId: string;
  readonly name: string;
  readonly periodStart: Temporal.PlainDate;
  readonly periodEnd: Temporal.PlainDate;
  readonly ownerId?: string;
  readonly status: "draft" | "approved" | "closed";
  readonly notes?: string;
}

/** An inspection finding. */
export interface InspectionFinding {
  readonly id: string;
  readonly organizationId: string;
  readonly inspectionId: string;
  readonly number: number;
  readonly type: string;
  readonly title: string;
  readonly description?: string;
  readonly clause?: string;
  readonly caseId?: string;
}

/** An inspection. */
export interface Inspection {
  readonly id: string;
  readonly organizationId: string;
  readonly programId?: string;
  readonly number: string;
  readonly kind: string;
  readonly title: string;
  readonly scope?: string;
  readonly criteria?: string;
  readonly auditeeType?: string;
  readonly auditeeId?: string;
  readonly leadId?: string;
  readonly plannedStart?: Temporal.PlainDate;
  readonly plannedEnd?: Temporal.PlainDate;
  readonly startedAt?: Temporal.Instant;
  readonly completedAt?: Temporal.Instant;
  readonly closedAt?: Temporal.Instant;
  readonly status:
    | "planned"
    | "in_progress"
    | "reporting"
    | "closed"
    | "cancelled";
  readonly summary?: string;
  readonly findings?: readonly InspectionFinding[];
}

/** The input of `schedule`. */
export interface InspectionInput {
  readonly title: string;
  readonly kind?: string;
  readonly scope?: string;
  readonly criteria?: string;
  readonly programId?: string;
  readonly leadId?: string;
  readonly plannedStart?: Temporal.PlainDate;
  readonly plannedEnd?: Temporal.PlainDate;
}

/** The changes `update` accepts. */
export interface InspectionChange {
  readonly title?: string;
  readonly scope?: string;
  readonly criteria?: string;
  readonly leadId?: string;
  readonly plannedStart?: Temporal.PlainDate;
  readonly plannedEnd?: Temporal.PlainDate;
}

/** The input of `addFinding`. */
export interface InspectionFindingInput {
  readonly type: string;
  readonly title: string;
  readonly description?: string;
  readonly clause?: string;
}

/** The filters `list` accepts. */
export interface InspectionListOptions {
  readonly programId?: string;
  readonly kind?: string;
  readonly status?: Inspection["status"];
  readonly leadId?: string;
}

/** The inspections client. */
export interface Inspections {
  saveProgram(
    organizationId: string,
    input: {
      readonly name: string;
      readonly periodStart: Temporal.PlainDate;
      readonly periodEnd: Temporal.PlainDate;
      readonly ownerId?: string;
      readonly notes?: string;
    },
  ): AsyncResult<InspectionProgram>;
  approveProgram(programId: string): AsyncResult<InspectionProgram>;
  closeProgram(programId: string): AsyncResult<InspectionProgram>;
  programs(organizationId: string): AsyncResult<readonly InspectionProgram[]>;
  schedule(
    organizationId: string,
    input: InspectionInput,
  ): AsyncResult<Inspection>;
  update(
    inspectionId: string,
    changes: InspectionChange,
  ): AsyncResult<Inspection>;
  start(inspectionId: string): AsyncResult<Inspection>;
  addFinding(
    inspectionId: string,
    input: InspectionFindingInput,
  ): AsyncResult<InspectionFinding>;
  updateFinding(
    findingId: string,
    changes: InspectionFindingInput,
  ): AsyncResult<InspectionFinding>;
  deleteFinding(findingId: string): AsyncResult<boolean>;
  raiseCase(findingId: string, kind?: string): AsyncResult<unknown>;
  complete(inspectionId: string, summary: string): AsyncResult<Inspection>;
  close(inspectionId: string): AsyncResult<Inspection>;
  cancel(inspectionId: string, reason: string): AsyncResult<Inspection>;
  get(inspectionId: string): AsyncResult<Inspection>;
  list(
    organizationId: string,
    options?: InspectionListOptions,
  ): AsyncResult<readonly Inspection[]>;
  notifyDue(): AsyncResult<number>;
}

/** `createInspections` options. */
export interface InspectionsOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly hooks?: NoInfer<BlockHooks<Inspections>>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

const programOf = (value: unknown, fn: string): InspectionProgram => {
  const row = recordOf(value, fn);
  const ownerId = optionalText(row["ownerId"]);
  const notes = optionalText(row["notes"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    name: textOf(row["name"]),
    periodStart: temporal().PlainDate.from(textOf(row["periodStart"])),
    periodEnd: temporal().PlainDate.from(textOf(row["periodEnd"])),
    ...(ownerId === undefined ? {} : { ownerId }),
    // SAFETY: inspection_programs.status has a check constraint on these three values.
    status: textOf(row["status"]) as InspectionProgram["status"],
    ...(notes === undefined ? {} : { notes }),
  };
};

const findingOf = (value: unknown, fn: string): InspectionFinding => {
  const row = recordOf(value, fn);
  const description = optionalText(row["description"]);
  const clause = optionalText(row["clause"]);
  const caseId = optionalText(row["caseId"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    inspectionId: textOf(row["inspectionId"]),
    number: Number(row["number"]),
    type: textOf(row["type"]),
    title: textOf(row["title"]),
    ...(description === undefined ? {} : { description }),
    ...(clause === undefined ? {} : { clause }),
    ...(caseId === undefined ? {} : { caseId }),
  };
};

const inspectionOf = (value: unknown, fn: string): Inspection => {
  const row = recordOf(value, fn);
  const text = (key: string): string | undefined => optionalText(row[key]);

  const date = (key: string): Temporal.PlainDate | undefined => {
    const value = text(key);

    return value === undefined ? undefined : temporal().PlainDate.from(value);
  };

  const instant = (key: string): Temporal.Instant | undefined =>
    optionalInstant(row[key]);

  const programId = text("programId");
  const scope = text("scope");
  const criteria = text("criteria");
  const auditeeType = text("auditeeType");
  const auditeeId = text("auditeeId");
  const leadId = text("leadId");
  const plannedStart = date("plannedStart");
  const plannedEnd = date("plannedEnd");
  const startedAt = instant("startedAt");
  const completedAt = instant("completedAt");
  const closedAt = instant("closedAt");
  const summary = text("summary");

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    ...(programId === undefined ? {} : { programId }),
    number: textOf(row["number"]),
    kind: textOf(row["kind"]),
    title: textOf(row["title"]),
    ...(scope === undefined ? {} : { scope }),
    ...(criteria === undefined ? {} : { criteria }),
    ...(auditeeType === undefined ? {} : { auditeeType }),
    ...(auditeeId === undefined ? {} : { auditeeId }),
    ...(leadId === undefined ? {} : { leadId }),
    ...(plannedStart === undefined ? {} : { plannedStart }),
    ...(plannedEnd === undefined ? {} : { plannedEnd }),
    ...(startedAt === undefined ? {} : { startedAt }),
    ...(completedAt === undefined ? {} : { completedAt }),
    ...(closedAt === undefined ? {} : { closedAt }),
    // SAFETY: inspections.status has a check constraint on these five values.
    status: textOf(row["status"]) as Inspection["status"],
    ...(summary === undefined ? {} : { summary }),
    ...(row["findings"] === undefined
      ? {}
      : {
          findings: recordsOf(row["findings"], `${fn}.findings`).map((item) =>
            findingOf(item, `${fn}.findings`),
          ),
        }),
  };
};

/** The `inspections` SQL module as typed calls. */
export function createInspections(options: InspectionsOptions): Inspections {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  blockFields(undefined, "inspection fields");

  const client: Inspections = {
    saveProgram: (organizationId, input) =>
      call(
        "save_inspection_program",
        {
          tenant: organizationId,
          name: input.name,
          period_start: input.periodStart.toString(),
          period_end: input.periodEnd.toString(),
          owner_id: input.ownerId ?? null,
          notes: input.notes ?? null,
          program_id: null,
        },
        (value) => programOf(value, "save_inspection_program"),
      ),
    approveProgram: (programId) =>
      call("approve_inspection_program", { program_id: programId }, (value) =>
        programOf(value, "approve_inspection_program"),
      ),
    closeProgram: (programId) =>
      call("close_inspection_program", { program_id: programId }, (value) =>
        programOf(value, "close_inspection_program"),
      ),
    programs: (organizationId) =>
      call(
        "list_inspection_programs",
        { tenant: organizationId },
        (value) =>
          recordsOf(value, "list_inspection_programs").map((row) =>
            programOf(row, "list_inspection_programs"),
          ),
      ),
    schedule: (organizationId, input) =>
      call(
        "schedule_inspection",
        {
          tenant: organizationId,
          input: {
            ...(input.programId === undefined
              ? {}
              : { programId: input.programId }),
            ...(input.kind === undefined ? {} : { kind: input.kind }),
            title: input.title,
            ...(input.scope === undefined ? {} : { scope: input.scope }),
            ...(input.criteria === undefined
              ? {}
              : { criteria: input.criteria }),
            ...(input.leadId === undefined ? {} : { leadId: input.leadId }),
            ...(input.plannedStart === undefined
              ? {}
              : { plannedStart: input.plannedStart.toString() }),
            ...(input.plannedEnd === undefined
              ? {}
              : { plannedEnd: input.plannedEnd.toString() }),
          },
        },
        (value) => inspectionOf(value, "schedule_inspection"),
      ),
    update: (inspectionId, changes) =>
      call(
        "update_inspection",
        { inspection_id: inspectionId, changes },
        (value) => inspectionOf(value, "update_inspection"),
      ),
    start: (inspectionId) =>
      call("start_inspection", { inspection_id: inspectionId }, (value) =>
        inspectionOf(value, "start_inspection"),
      ),
    addFinding: (inspectionId, input) =>
      call(
        "add_inspection_finding",
        {
          inspection_id: inspectionId,
          type: input.type,
          title: input.title,
          description: input.description ?? null,
          clause: input.clause ?? null,
        },
        (value) => findingOf(value, "add_inspection_finding"),
      ),
    updateFinding: (findingId, changes) =>
      call(
        "update_inspection_finding",
        { finding_id: findingId, changes },
        (value) => findingOf(value, "update_inspection_finding"),
      ),
    deleteFinding: (findingId) =>
      call(
        "delete_inspection_finding",
        { finding_id: findingId },
        (value) => value === true,
      ),
    raiseCase: (findingId, kind) =>
      call(
        "raise_inspection_finding_case",
        { finding_id: findingId, kind: kind ?? "finding" },
        (value) => value,
      ),
    complete: (inspectionId, summary) =>
      call(
        "complete_inspection",
        { inspection_id: inspectionId, summary },
        (value) => inspectionOf(value, "complete_inspection"),
      ),
    close: (inspectionId) =>
      call("close_inspection", { inspection_id: inspectionId }, (value) =>
        inspectionOf(value, "close_inspection"),
      ),
    cancel: (inspectionId, reason) =>
      call(
        "cancel_inspection",
        { inspection_id: inspectionId, reason },
        (value) => inspectionOf(value, "cancel_inspection"),
      ),
    get: (inspectionId) =>
      call("get_inspection", { inspection_id: inspectionId }, (value) =>
        inspectionOf(value, "get_inspection"),
      ),
    list: (organizationId, input) =>
      call(
        "list_inspections",
        {
          tenant: organizationId,
          filters: {
            ...(input?.programId === undefined
              ? {}
              : { programId: input.programId }),
            ...(input?.kind === undefined ? {} : { kind: input.kind }),
            ...(input?.status === undefined ? {} : { status: input.status }),
            ...(input?.leadId === undefined ? {} : { leadId: input.leadId }),
          },
        },
        (value) =>
          recordsOf(value, "list_inspections").map((row) =>
            inspectionOf(row, "list_inspections"),
          ),
      ),
    notifyDue: () => call("notify_due_inspections", {}, Number),
  };

  return withBlockHooks(client, options.hooks, {
    block: "inspections",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
